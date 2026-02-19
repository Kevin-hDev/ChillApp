// =============================================================
// FIX-034 : Heartbeat securise challenge-response
// GAP-034: Heartbeat securise absent (P1)
// Cible: lib/core/security/secure_heartbeat.dart (nouveau)
// =============================================================
//
// PROBLEME : Aucun heartbeat entre l'app Flutter et le daemon Go.
// Impossible de detecter si le daemon a plante, est compromis,
// ou si un MITM intercepte le canal IPC.
//
// SOLUTION :
// 1. Challenge-response cryptographique periodique
// 2. L'app envoie un nonce, le daemon repond HMAC(nonce, sharedKey)
// 3. Timeout strict (5 secondes)
// 4. 3 echecs consecutifs = connexion fermee (fail closed)
// =============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Etat du heartbeat.
enum HeartbeatState {
  /// Heartbeat actif et fonctionnel.
  healthy,

  /// 1-2 echecs recents, surveillance.
  degraded,

  /// 3+ echecs, daemon considere mort ou compromis.
  dead,

  /// Heartbeat non demarre.
  stopped,
}

/// Resultat d'un seul battement.
class HeartbeatResult {
  final bool success;
  final Duration? latency;
  final String? error;
  final DateTime timestamp;

  HeartbeatResult({
    required this.success,
    this.latency,
    this.error,
  }) : timestamp = DateTime.now();
}

/// Callback pour envoyer un challenge au daemon et recevoir la reponse.
/// Le daemon doit calculer HMAC-SHA256(challenge, sharedKey) et retourner le hex.
typedef ChallengeCallback = Future<String?> Function(String challengeHex);

/// Callback quand l'etat du heartbeat change.
typedef HeartbeatStateCallback = void Function(
    HeartbeatState oldState, HeartbeatState newState);

/// Heartbeat securise avec challenge-response HMAC.
class SecureHeartbeat {
  /// Cle partagee pour le HMAC (generee au demarrage, echangee via IPC auth).
  final Uint8List _sharedKey;

  /// Intervalle entre les heartbeats.
  final Duration interval;

  /// Timeout pour chaque challenge.
  final Duration timeout;

  /// Nombre d'echecs avant de declarer le daemon mort.
  final int maxConsecutiveFailures;

  /// Callback pour envoyer le challenge au daemon.
  final ChallengeCallback sendChallenge;

  /// Callback quand l'etat change.
  HeartbeatStateCallback? onStateChange;

  HeartbeatState _state = HeartbeatState.stopped;
  Timer? _timer;
  int _consecutiveFailures = 0;
  final List<HeartbeatResult> _history = [];
  final Random _random = Random.secure();

  SecureHeartbeat({
    required Uint8List sharedKey,
    required this.sendChallenge,
    this.interval = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 5),
    this.maxConsecutiveFailures = 3,
    this.onStateChange,
  }) : _sharedKey = Uint8List.fromList(sharedKey);

  /// Etat actuel.
  HeartbeatState get state => _state;

  /// Historique des derniers battements.
  List<HeartbeatResult> get history => List.unmodifiable(_history);

  /// Latence moyenne des 10 derniers succes.
  Duration? get averageLatency {
    final successes = _history
        .where((r) => r.success && r.latency != null)
        .toList();
    if (successes.isEmpty) return null;
    final recent = successes.length > 10
        ? successes.sublist(successes.length - 10)
        : successes;
    final totalMs = recent.fold<int>(
        0, (sum, r) => sum + r.latency!.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ recent.length);
  }

  /// Demarre le heartbeat periodique.
  void start() {
    stop();
    _state = HeartbeatState.healthy;
    _consecutiveFailures = 0;
    _timer = Timer.periodic(interval, (_) => _beat());
    // Premier battement immediat
    _beat();
  }

  /// Arrete le heartbeat.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _updateState(HeartbeatState.stopped);
  }

  /// Execute un battement unique.
  Future<HeartbeatResult> _beat() async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Generer un challenge aleatoire (32 bytes)
      final challenge = _generateChallenge();
      final challengeHex = _bytesToHex(challenge);

      // 2. Calculer la reponse attendue
      final expectedHmac = Hmac(sha256, _sharedKey);
      final expectedDigest = expectedHmac.convert(challenge);
      final expectedHex = expectedDigest.toString();

      // 3. Envoyer le challenge avec timeout
      final responseHex = await sendChallenge(challengeHex)
          .timeout(timeout, onTimeout: () => null);

      stopwatch.stop();

      // 4. Verifier la reponse
      if (responseHex == null) {
        return _recordResult(HeartbeatResult(
          success: false,
          latency: stopwatch.elapsed,
          error: 'Timeout ($timeout)',
        ));
      }

      // Comparaison en temps constant
      if (!_constantTimeEquals(expectedHex, responseHex)) {
        return _recordResult(HeartbeatResult(
          success: false,
          latency: stopwatch.elapsed,
          error: 'Reponse HMAC invalide (daemon compromis ?)',
        ));
      }

      // Succes
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

  /// Genere un challenge aleatoire de 32 bytes.
  Uint8List _generateChallenge() {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Enregistre le resultat et met a jour l'etat.
  HeartbeatResult _recordResult(HeartbeatResult result) {
    _history.add(result);
    // Garder les 100 derniers
    if (_history.length > 100) {
      _history.removeAt(0);
    }

    if (result.success) {
      _consecutiveFailures = 0;
      if (_state == HeartbeatState.degraded) {
        _updateState(HeartbeatState.healthy);
      }
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxConsecutiveFailures) {
        _updateState(HeartbeatState.dead);
      } else if (_consecutiveFailures >= 1) {
        _updateState(HeartbeatState.degraded);
      }
    }

    return result;
  }

  void _updateState(HeartbeatState newState) {
    if (_state != newState) {
      final oldState = _state;
      _state = newState;
      onStateChange?.call(oldState, newState);
    }
  }

  /// Comparaison en temps constant de deux strings hex.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Libere les ressources.
  void dispose() {
    stop();
    // Zeroiser la cle partagee
    for (int i = 0; i < _sharedKey.length; i++) {
      _sharedKey[i] = 0;
    }
    _history.clear();
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Cote Flutter (lib/features/tailscale/tailscale_provider.dart) :
//
//   final heartbeat = SecureHeartbeat(
//     sharedKey: ipcSharedKey,
//     sendChallenge: (challengeHex) async {
//       // Envoyer {"type": "heartbeat", "challenge": challengeHex}
//       // au daemon via stdin
//       daemonProcess.stdin.writeln(
//         jsonEncode({'type': 'heartbeat', 'challenge': challengeHex}),
//       );
//       // Lire la reponse du daemon
//       final response = await daemonStdout.first
//           .timeout(Duration(seconds: 5));
//       final json = jsonDecode(response);
//       return json['response'] as String?;
//     },
//     onStateChange: (old, newState) {
//       if (newState == HeartbeatState.dead) {
//         // Daemon mort ou compromis — FAIL CLOSED
//         failGuard.forceOpen('Heartbeat dead');
//         killDaemon();
//       }
//     },
//   );
//   heartbeat.start();
//
// Cote Go (tailscale-daemon/main.go) :
//
//   // Recevoir le challenge
//   challenge := msg["challenge"]
//   // Calculer HMAC-SHA256
//   mac := hmac.New(sha256.New, sharedKey)
//   mac.Write(hexDecode(challenge))
//   response := hex.EncodeToString(mac.Sum(nil))
//   // Retourner la reponse
//   sendJSON(map[string]string{"type":"heartbeat","response":response})
// =============================================================
