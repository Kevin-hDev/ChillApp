// =============================================================
// FIX-034 : Heartbeat sécurisé challenge-response
// GAP-034: Heartbeat sécurisé absent (P1)
// =============================================================
//
// PROBLEME : Aucun heartbeat entre l'app Flutter et le daemon Go.
// Impossible de détecter si le daemon a planté, est compromis,
// ou si un MITM intercepte le canal IPC.
//
// SOLUTION :
// 1. Challenge-response cryptographique périodique (HMAC-SHA256)
// 2. L'app envoie un nonce aléatoire (32 bytes CSPRNG)
// 3. Le daemon répond HMAC-SHA256(sharedKey, challenge)
// 4. Comparaison en temps constant (résistant aux timing attacks)
// 5. Timeout strict de 5 secondes
// 6. Machine d'état : healthy → degraded → dead
// 7. 3 échecs consécutifs = daemon mort ou compromis (fail closed)
// =============================================================

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// État du heartbeat.
enum HeartbeatState {
  /// Heartbeat actif et fonctionnel — tous les challenges réussis.
  healthy,

  /// 1 à 2 échecs récents — surveillance renforcée.
  degraded,

  /// 3 échecs consécutifs ou plus — daemon considéré mort ou compromis.
  dead,

  /// Heartbeat non démarré ou arrêté manuellement.
  stopped,
}

/// Résultat d'un seul battement de heartbeat.
class HeartbeatResult {
  /// Indique si le challenge a réussi.
  final bool success;

  /// Latence mesurée du round-trip challenge/réponse.
  final Duration? latency;

  /// Message d'erreur si l'échec, null si succès.
  final String? error;

  /// Horodatage du battement.
  final DateTime timestamp;

  HeartbeatResult({
    required this.success,
    this.latency,
    this.error,
  }) : timestamp = DateTime.now();
}

/// Callback envoyant un challenge (hex) au daemon et recevant la réponse (hex).
///
/// Le daemon doit calculer HMAC-SHA256(sharedKey, challengeBytes) et
/// retourner le résultat en hexadécimal.
/// Retourne null en cas de timeout ou d'erreur.
typedef ChallengeCallback = Future<List<int>?> Function(List<int> challenge);

/// Callback appelé lors d'un changement d'état du heartbeat.
typedef HeartbeatStateCallback = void Function(
    HeartbeatState oldState, HeartbeatState newState);

/// Heartbeat sécurisé avec challenge-response HMAC-SHA256.
///
/// EXEMPLE D'UTILISATION :
/// ```dart
/// final heartbeat = SecureHeartbeat(
///   sharedKey: ipcSharedKey,
///   onStateChange: (old, newState) {
///     if (newState == HeartbeatState.dead) {
///       // Daemon mort — FAIL CLOSED
///       killDaemon();
///     }
///   },
/// );
///
/// heartbeat.start((challenge) async {
///   // Envoyer le challenge au daemon et recevoir la réponse
///   return await sendToDaemon(challenge);
/// });
/// ```
class SecureHeartbeat {
  /// Clé partagée pour le HMAC (échangée via IPC auth au démarrage).
  final Uint8List _sharedKey;

  /// Intervalle entre les battements (défaut: 10 secondes).
  final Duration interval;

  /// Timeout pour chaque challenge (défaut: 5 secondes).
  final Duration timeout;

  /// Nombre d'échecs consécutifs avant de déclarer le daemon mort.
  final int maxFailures;

  /// Callback appelé lors d'un changement d'état.
  HeartbeatStateCallback? onStateChange;

  HeartbeatState _state = HeartbeatState.stopped;
  Timer? _timer;
  int _consecutiveFailures = 0;
  final List<HeartbeatResult> _history = [];
  final Random _random = Random.secure();

  /// Constructeur principal.
  ///
  /// [sharedKey] : clé partagée avec le daemon (min. 32 bytes recommandé)
  /// [interval] : intervalle entre les heartbeats (défaut 10 secondes)
  /// [maxFailures] : échecs consécutifs avant de passer à dead (défaut 3)
  /// [onStateChange] : callback lors des transitions d'état
  SecureHeartbeat({
    required List<int> sharedKey,
    this.interval = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 5),
    this.maxFailures = 3,
    this.onStateChange,
  }) : _sharedKey = Uint8List.fromList(sharedKey);

  /// État actuel du heartbeat.
  HeartbeatState get state => _state;

  /// Historique des 100 derniers battements (lecture seule).
  List<HeartbeatResult> get history => List.unmodifiable(_history);

  /// Latence moyenne des 10 derniers succès.
  /// Retourne null s'il n'y a aucun succès enregistré.
  Duration? get averageLatency {
    final successes = _history
        .where((r) => r.success && r.latency != null)
        .toList();
    if (successes.isEmpty) return null;
    final recent = successes.length > 10
        ? successes.sublist(successes.length - 10)
        : successes;
    final totalMs =
        recent.fold<int>(0, (sum, r) => sum + r.latency!.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ recent.length);
  }

  /// Démarre le heartbeat périodique.
  ///
  /// [sendChallenge] : callback pour envoyer le challenge au daemon.
  /// Le premier battement est exécuté immédiatement.
  void start(ChallengeCallback sendChallenge) {
    stop();
    _state = HeartbeatState.healthy;
    _consecutiveFailures = 0;

    // Premier battement immédiat, puis périodique
    beat(sendChallenge);
    _timer = Timer.periodic(interval, (_) => beat(sendChallenge));
  }

  /// Arrête le heartbeat périodique.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _updateState(HeartbeatState.stopped);
  }

  /// Exécute un seul battement de heartbeat.
  ///
  /// Cette méthode est publique pour permettre les tests unitaires.
  /// En production, utiliser [start] pour le heartbeat périodique.
  Future<HeartbeatResult> beat(ChallengeCallback sendChallenge) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Générer un challenge aléatoire (32 bytes CSPRNG)
      final challenge = _generateChallenge();

      // 2. Calculer la réponse attendue : HMAC-SHA256(sharedKey, challenge)
      final hmac = Hmac(sha256, _sharedKey);
      final expectedDigest = hmac.convert(challenge);
      final expectedBytes = Uint8List.fromList(expectedDigest.bytes);

      // 3. Envoyer le challenge avec timeout strict
      final responseBytes = await sendChallenge(List.unmodifiable(challenge))
          .timeout(timeout, onTimeout: () => null);

      stopwatch.stop();

      // 4. Vérifier la réponse : null = timeout
      if (responseBytes == null) {
        return _recordResult(HeartbeatResult(
          success: false,
          latency: stopwatch.elapsed,
          error: 'Timeout après ${timeout.inSeconds}s',
        ));
      }

      // 5. Comparaison en temps constant (résistant aux timing attacks)
      if (!_constantTimeEquals(expectedBytes, Uint8List.fromList(responseBytes))) {
        return _recordResult(HeartbeatResult(
          success: false,
          latency: stopwatch.elapsed,
          error: 'Réponse HMAC invalide — daemon potentiellement compromis',
        ));
      }

      // Succès
      return _recordResult(HeartbeatResult(
        success: true,
        latency: stopwatch.elapsed,
      ));
    } catch (e) {
      stopwatch.stop();
      return _recordResult(HeartbeatResult(
        success: false,
        latency: stopwatch.elapsed,
        error: 'Exception: $e',
      ));
    }
  }

  /// Génère un challenge aléatoire de 32 bytes via CSPRNG.
  Uint8List _generateChallenge() {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Enregistre le résultat et met à jour la machine d'état.
  HeartbeatResult _recordResult(HeartbeatResult result) {
    _history.add(result);
    // Garder uniquement les 100 derniers résultats
    if (_history.length > 100) {
      _history.removeAt(0);
    }

    if (result.success) {
      // Succès : réinitialiser le compteur et passer/rester à healthy
      // SAUF si dead — l'état dead est terminal, nécessite un redémarrage
      // explicite via stop()/start() pour éviter qu'un daemon compromis
      // puisse reprendre une apparence saine avec un seul succès.
      _consecutiveFailures = 0;
      if (_state != HeartbeatState.healthy && _state != HeartbeatState.dead) {
        _updateState(HeartbeatState.healthy);
      }
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxFailures) {
        // Seuil critique atteint — fail closed
        _updateState(HeartbeatState.dead);
      } else if (_consecutiveFailures >= 1 &&
          _state != HeartbeatState.dead) {
        _updateState(HeartbeatState.degraded);
      }
    }

    return result;
  }

  /// Met à jour l'état et notifie le callback si l'état a changé.
  void _updateState(HeartbeatState newState) {
    if (_state != newState) {
      final oldState = _state;
      _state = newState;
      onStateChange?.call(oldState, newState);
    }
  }

  /// Comparaison en temps constant de deux tableaux de bytes.
  ///
  /// Résistant aux attaques par timing : le temps d'exécution est
  /// identique que les tableaux soient égaux ou non.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Libère les ressources et efface la clé de la mémoire.
  void dispose() {
    stop();
    // Zéroïser la clé partagée pour éviter qu'elle reste en mémoire
    for (int i = 0; i < _sharedKey.length; i++) {
      _sharedKey[i] = 0;
    }
    _history.clear();
  }
}
