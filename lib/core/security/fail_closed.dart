// =============================================================
// FIX-032 : Politique Fail Closed + Circuit Breaker
// GAP-032: Pas de fail closed — fallback non securise (P0)
// Cible: lib/core/security/fail_closed.dart
// =============================================================
//
// PROBLEME : Si le daemon plante ou Tailscale est deconnecte,
// l'app pourrait tenter un fallback non securise (connexion SSH
// directe sur le reseau local). C'est une faille critique (CWE-636).
//
// SOLUTION :
// 1. Toute operation reseau passe par le FailClosedGuard
// 2. Avant chaque connexion : verifier Tailscale + daemon actifs
// 3. Si indisponible : BLOQUER, jamais de fallback
// 4. Auto-verrouillage apres 3 echecs consecutifs pendant 5 minutes
//
// Etats du circuit :
//   closed   → tout fonctionne, connexions autorisees
//   halfOpen → periode de test apres expiration du blocage
//   open     → circuit bloque, TOUTES les connexions refusees
// =============================================================

import 'dart:io';

/// Les trois etats possibles du circuit reseau.
enum NetworkCircuitState {
  /// Tout est fonctionnel — connexions autorisees.
  closed,

  /// Quelques erreurs recentes — une tentative de reconnexion autorisee.
  halfOpen,

  /// Circuit ouvert — toutes les connexions bloquees.
  open,
}

/// Raison d'un blocage de connexion.
class BlockReason {
  final String code;
  final String message;
  final DateTime timestamp;

  const BlockReason({
    required this.code,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() => '[$code] $message (${timestamp.toIso8601String()})';
}

/// Callback appele quand une connexion est bloquee.
typedef ConnectionBlockedCallback = void Function(BlockReason reason);

/// Gardien Fail-Closed pour toutes les connexions reseau de ChillApp.
///
/// Aucune connexion ne passe si :
///   - Tailscale n'est pas connecte
///   - Le daemon chill-tailscale n'est pas actif
///   - La destination n'est pas dans le reseau Tailscale
///   - Le circuit est ouvert (trop d'echecs consecutifs)
///
/// Pattern Circuit Breaker :
///   - [maxConsecutiveFailures] echecs → circuit OPEN (bloque)
///   - Apres [circuitOpenDuration] → circuit HALF_OPEN (une tentative)
///   - Succes en HALF_OPEN → circuit CLOSED (normal)
///   - Echec en HALF_OPEN → circuit OPEN a nouveau
class FailClosedGuard {
  /// Nombre d'echecs consecutifs avant ouverture du circuit (defaut : 3).
  final int maxConsecutiveFailures;

  /// Duree de blocage apres ouverture du circuit (defaut : 5 minutes).
  final Duration circuitOpenDuration;

  /// Callback optionnel appele a chaque blocage (pour les logs d'audit).
  ConnectionBlockedCallback? onBlocked;

  NetworkCircuitState _state = NetworkCircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenedAt;
  final List<BlockReason> _blockLog = [];

  FailClosedGuard({
    this.maxConsecutiveFailures = 3,
    this.circuitOpenDuration = const Duration(minutes: 5),
    this.onBlocked,
  });

  /// Etat actuel du circuit.
  NetworkCircuitState get state => _state;

  /// Nombre d'echecs consecutifs en cours.
  int get consecutiveFailures => _consecutiveFailures;

  /// Log des blocages recents (max 100 entrees).
  List<BlockReason> get blockLog => List.unmodifiable(_blockLog);

  // ============================================================
  // API publique
  // ============================================================

  /// Verifie si une nouvelle connexion est autorisee.
  ///
  /// Retourne true si OK, false si le circuit est ouvert.
  /// Ne fait pas les verifications systeme — utiliser [checkConnection]
  /// pour la verification complete.
  bool canConnect() {
    if (_state == NetworkCircuitState.open) {
      // Verifier si le delai d'expiration est ecoule
      if (_circuitOpenedAt != null) {
        final elapsed = DateTime.now().difference(_circuitOpenedAt!);
        if (elapsed >= circuitOpenDuration) {
          // Passer en half-open pour autoriser une tentative
          _state = NetworkCircuitState.halfOpen;
          return true;
        }
      }
      return false;
    }
    // closed ou halfOpen : autorise
    return true;
  }

  /// Enregistre un echec de connexion.
  ///
  /// Apres [maxConsecutiveFailures] echecs consecutifs, le circuit
  /// passe en etat OPEN et bloque toutes les connexions pendant
  /// [circuitOpenDuration].
  void recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= maxConsecutiveFailures) {
      _state = NetworkCircuitState.open;
      _circuitOpenedAt = DateTime.now();
      _addBlock('CIRCUIT_OPEN',
          'Circuit ouvert apres $_consecutiveFailures echecs consecutifs. '
          'Bloque pendant ${circuitOpenDuration.inMinutes} minutes.');
    }
  }

  /// Enregistre un succes et remet le compteur a zero.
  ///
  /// Si le circuit etait en HALF_OPEN, il repasse en CLOSED.
  void recordSuccess() {
    _consecutiveFailures = 0;
    if (_state == NetworkCircuitState.halfOpen) {
      _state = NetworkCircuitState.closed;
    }
  }

  /// Valide qu'une destination est dans le reseau Tailscale.
  ///
  /// [host] : adresse IP ou hostname cible.
  /// [port] : port de connexion (doit etre 22 pour SSH).
  ///
  /// Retourne true si la destination est autorisee.
  /// Ranges autorises :
  ///   - IPv4 : 100.64.0.0/10 (bits 100.64–100.127)
  ///   - IPv6 : fd7a:115c:a1e0::/48
  ///   - Hostname : doit terminer par .ts.net
  bool validateDestination(String host, int port) {
    // Verifier le port : seul SSH (22) est autorise
    if (port != 22) {
      _addBlock('INVALID_PORT',
          'Port $port non autorise. Seul le port SSH (22) est permis.');
      return false;
    }

    // Verifier l'adresse
    final ip = InternetAddress.tryParse(host);

    if (ip == null) {
      // Hostname — doit etre un .ts.net (reseau Tailscale)
      if (!host.endsWith('.ts.net')) {
        _addBlock('NON_TAILSCALE_HOST',
            'Hote "$host" n\'est pas un hote Tailscale (.ts.net). Refuse.');
        return false;
      }
      return true;
    }

    // IPv4 Tailscale : 100.64.0.0/10
    // Premier octet = 100, deuxieme octet entre 64 et 127 (bits 01xxxxxx)
    if (ip.type == InternetAddressType.IPv4) {
      final bytes = ip.rawAddress;
      if (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) {
        return true;
      }
    }

    // IPv6 Tailscale : fd7a:115c:a1e0::/48
    if (ip.type == InternetAddressType.IPv6) {
      final bytes = ip.rawAddress;
      if (bytes[0] == 0xfd &&
          bytes[1] == 0x7a &&
          bytes[2] == 0x11 &&
          bytes[3] == 0x5c) {
        return true;
      }
    }

    _addBlock('NON_TAILSCALE_IP',
        'IP "$host" hors du reseau Tailscale (100.64.0.0/10 ou fd7a:115c:a1e0::/48). Refuse.');
    return false;
  }

  /// Verification complete avant connexion : Tailscale + daemon + IP locale.
  ///
  /// Retourne null si tout est OK, ou une [BlockReason] si bloque.
  Future<BlockReason?> checkConnection() async {
    // Circuit ouvert : verifier si le delai est ecoule
    if (_state == NetworkCircuitState.open) {
      if (_circuitOpenedAt != null) {
        final elapsed = DateTime.now().difference(_circuitOpenedAt!);
        if (elapsed >= circuitOpenDuration) {
          _state = NetworkCircuitState.halfOpen;
          // Laisser passer une tentative (continue les verifications)
        } else {
          return _block('CIRCUIT_OPEN',
              'Circuit ouvert depuis ${elapsed.inMinutes}min. '
              'Toutes les connexions bloquees.');
        }
      }
    }

    // Verification 1 : Tailscale connecte ?
    final tailscaleOk = await _checkTailscale();
    if (!tailscaleOk) {
      recordFailure();
      return _block('TAILSCALE_DOWN',
          'Tailscale non connecte. Connexion refusee (fail closed).');
    }

    // Verification 2 : daemon chill-tailscale actif ?
    final daemonOk = await _checkDaemon();
    if (!daemonOk) {
      recordFailure();
      return _block('DAEMON_DOWN',
          'Daemon chill-tailscale non actif. Connexion refusee.');
    }

    // Verification 3 : IP Tailscale locale valide ?
    final ipOk = await _checkTailscaleIP();
    if (!ipOk) {
      recordFailure();
      return _block('NO_TAILSCALE_IP',
          'Aucune IP Tailscale locale detectee. Connexion refusee.');
    }

    // Tout OK
    recordSuccess();
    return null;
  }

  /// Wrapper securise pour executer une operation reseau.
  ///
  /// Verifie la destination et l'etat du circuit avant d'executer.
  /// En cas de blocage, appelle [onBlockedReturn] plutot que de lancer une exception.
  Future<T> executeSecure<T>({
    required String destination,
    required int port,
    required Future<T> Function() operation,
    required T Function(BlockReason) onBlockedReturn,
  }) async {
    // 1. Valider la destination
    if (!validateDestination(destination, port)) {
      final reason = _blockLog.isNotEmpty
          ? _blockLog.last
          : BlockReason(
              code: 'INVALID_DESTINATION',
              message: 'Destination invalide',
              timestamp: DateTime.now(),
            );
      return onBlockedReturn(reason);
    }

    // 2. Verifier l'etat du circuit
    final circuitBlock = await checkConnection();
    if (circuitBlock != null) {
      return onBlockedReturn(circuitBlock);
    }

    // 3. Executer l'operation
    try {
      final result = await operation();
      return result;
    } catch (e) {
      recordFailure();
      final reason = _block('CONNECTION_ERROR', 'Erreur de connexion : $e');
      return onBlockedReturn(reason);
    }
  }

  /// Force le circuit en etat OPEN (blocage d'urgence immediat).
  ///
  /// [reason] : raison du blocage force (pour le log d'audit).
  void forceOpen([String reason = 'Blocage force par securite']) {
    _state = NetworkCircuitState.open;
    _circuitOpenedAt = DateTime.now();
    _addBlock('FORCED_OPEN', 'Circuit force ouvert : $reason');
  }

  /// Remet le circuit en etat CLOSED (apres resolution du probleme).
  void reset() {
    _state = NetworkCircuitState.closed;
    _consecutiveFailures = 0;
    _circuitOpenedAt = null;
  }

  // ============================================================
  // Verifications systeme internes
  // ============================================================

  Future<bool> _checkTailscale() async {
    try {
      final result = await Process.run('tailscale', ['status', '--json']);
      if (result.exitCode != 0) return false;
      return result.stdout.toString().contains('"BackendState":"Running"');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkDaemon() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-Process -Name chill-tailscale -ErrorAction SilentlyContinue',
        ]);
        return result.exitCode == 0 &&
            result.stdout.toString().contains('chill-tailscale');
      } else {
        final result = await Process.run('pgrep', ['-f', 'chill-tailscale']);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkTailscaleIP() async {
    try {
      final result = await Process.run('tailscale', ['ip', '-4']);
      if (result.exitCode != 0) return false;
      final ip = result.stdout.toString().trim();
      // Verifier que c'est bien une IP 100.x.x.x (Tailscale)
      return ip.startsWith('100.');
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // Gestion du log de blocage
  // ============================================================

  /// Cree un BlockReason, l'ajoute au log et notifie le callback.
  BlockReason _block(String code, String message) {
    final reason = BlockReason(
      code: code,
      message: message,
      timestamp: DateTime.now(),
    );
    _addBlockReason(reason);
    return reason;
  }

  void _addBlock(String code, String message) {
    _block(code, message);
  }

  void _addBlockReason(BlockReason reason) {
    _blockLog.add(reason);
    // Garder seulement les 100 derniers blocages
    if (_blockLog.length > 100) {
      _blockLog.removeAt(0);
    }
    onBlocked?.call(reason);
  }
}
