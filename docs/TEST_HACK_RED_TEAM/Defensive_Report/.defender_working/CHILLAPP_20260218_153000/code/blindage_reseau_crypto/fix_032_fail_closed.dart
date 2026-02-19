// =============================================================
// FIX-032 : Politique Fail Closed
// GAP-032: Pas de fail closed — fallback non securise (P0)
// Cible: lib/core/security/fail_closed.dart (nouveau)
// =============================================================
//
// PROBLEME : Si le daemon plante ou Tailscale est deconnecte,
// l'app pourrait tenter un fallback non securise (connexion SSH
// directe sur le reseau local par exemple). C'est une faille
// critique (CWE-636).
//
// SOLUTION :
// 1. Toute operation reseau passe par le FailClosedGuard
// 2. Avant chaque connexion : verifier Tailscale + daemon actifs
// 3. Si indisponible : BLOQUER, jamais fallback
// 4. Auto-verrouillage apres N echecs consecutifs
// =============================================================

import 'dart:io';
import 'dart:async';

/// Etat du circuit reseau.
enum NetworkCircuitState {
  /// Tout est fonctionnel.
  closed,

  /// Quelques erreurs recentes, surveillance accrue.
  halfOpen,

  /// Circuit ouvert — toutes les connexions bloquees.
  open,
}

/// Raison du blocage.
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

/// Gardien Fail-Closed pour les connexions reseau.
/// Aucune connexion ne passe sans Tailscale actif et daemon valide.
class FailClosedGuard {
  /// Nombre d'echecs consecutifs avant ouverture du circuit.
  final int maxConsecutiveFailures;

  /// Duree minimale du circuit ouvert avant tentative de reset.
  final Duration circuitOpenDuration;

  NetworkCircuitState _state = NetworkCircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenedAt;
  final List<BlockReason> _blockLog = [];
  ConnectionBlockedCallback? onBlocked;

  FailClosedGuard({
    this.maxConsecutiveFailures = 3,
    this.circuitOpenDuration = const Duration(minutes: 5),
    this.onBlocked,
  });

  /// Etat actuel du circuit.
  NetworkCircuitState get state => _state;

  /// Log des blocages recents.
  List<BlockReason> get blockLog => List.unmodifiable(_blockLog);

  /// Verifie si une connexion est autorisee.
  /// Retourne null si OK, ou une BlockReason si bloquee.
  Future<BlockReason?> checkConnection() async {
    // Circuit ouvert = tout bloque
    if (_state == NetworkCircuitState.open) {
      // Verifier si le delai est ecoule pour tenter un reset
      if (_circuitOpenedAt != null) {
        final elapsed = DateTime.now().difference(_circuitOpenedAt!);
        if (elapsed >= circuitOpenDuration) {
          _state = NetworkCircuitState.halfOpen;
          // Laisser passer UNE tentative
        } else {
          return _block('CIRCUIT_OPEN',
              'Circuit ouvert depuis ${elapsed.inMinutes}min. '
              'Toutes les connexions bloquees.');
        }
      }
    }

    // Verification 1 : Tailscale est-il connecte ?
    final tailscaleOk = await _checkTailscale();
    if (!tailscaleOk) {
      _recordFailure();
      return _block('TAILSCALE_DOWN',
          'Tailscale non connecte. Connexion refusee (fail closed).');
    }

    // Verification 2 : Le daemon chill-tailscale est-il actif ?
    final daemonOk = await _checkDaemon();
    if (!daemonOk) {
      _recordFailure();
      return _block('DAEMON_DOWN',
          'Daemon chill-tailscale non actif. Connexion refusee.');
    }

    // Verification 3 : L'interface Tailscale a une IP valide ?
    final ipOk = await _checkTailscaleIP();
    if (!ipOk) {
      _recordFailure();
      return _block('NO_TAILSCALE_IP',
          'Aucune IP Tailscale detectee. Connexion refusee.');
    }

    // Tout OK — reset du compteur
    _consecutiveFailures = 0;
    if (_state == NetworkCircuitState.halfOpen) {
      _state = NetworkCircuitState.closed;
    }
    return null;
  }

  /// Verifie une adresse IP de destination.
  /// Autorise UNIQUEMENT les IPs Tailscale (100.64.0.0/10).
  BlockReason? validateDestination(String host) {
    // Verifier que c'est une IP Tailscale
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      // Hostname — doit etre un .ts.net
      if (!host.endsWith('.ts.net')) {
        return _block('NON_TAILSCALE_HOST',
            'Hote "$host" n\'est pas un hote Tailscale (.ts.net). Connexion refusee.');
      }
      return null;
    }

    // Verifier le range 100.64.0.0/10
    if (ip.type == InternetAddressType.IPv4) {
      final bytes = ip.rawAddress;
      // 100.64.0.0/10 = premier octet 100, deuxieme: bits 01xxxxxx (64-127)
      if (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) {
        return null; // IP Tailscale valide
      }
    }

    // IPv6 Tailscale : fd7a:115c:a1e0::/48
    if (ip.type == InternetAddressType.IPv6) {
      final bytes = ip.rawAddress;
      if (bytes[0] == 0xfd && bytes[1] == 0x7a &&
          bytes[2] == 0x11 && bytes[3] == 0x5c) {
        return null; // IPv6 Tailscale valide
      }
    }

    return _block('NON_TAILSCALE_IP',
        'IP "$host" n\'est pas dans le reseau Tailscale. Connexion refusee.');
  }

  /// Wrapper securise pour executer une connexion.
  /// Verifie TOUT avant, bloque sinon.
  Future<T> executeSecure<T>({
    required String destination,
    required Future<T> Function() operation,
    required T Function(BlockReason) onBlockedReturn,
  }) async {
    // 1. Verifier la destination
    final destBlock = validateDestination(destination);
    if (destBlock != null) {
      return onBlockedReturn(destBlock);
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
      _recordFailure();
      final reason = _block('CONNECTION_ERROR', 'Erreur de connexion: $e');
      return onBlockedReturn(reason);
    }
  }

  /// Force le circuit ouvert (urgence).
  void forceOpen(String reason) {
    _state = NetworkCircuitState.open;
    _circuitOpenedAt = DateTime.now();
    _block('FORCED_OPEN', 'Circuit force ouvert: $reason');
  }

  /// Reset le circuit (apres resolution du probleme).
  void reset() {
    _state = NetworkCircuitState.closed;
    _consecutiveFailures = 0;
    _circuitOpenedAt = null;
  }

  // === Verifications internes ===

  Future<bool> _checkTailscale() async {
    try {
      final result = await Process.run('tailscale', ['status', '--json']);
      if (result.exitCode != 0) return false;
      // Verifier que BackendState est Running
      final stdout = result.stdout.toString();
      return stdout.contains('"BackendState":"Running"');
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
      // Verifier que c'est bien une IP 100.x.x.x
      return ip.startsWith('100.');
    } catch (_) {
      return false;
    }
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= maxConsecutiveFailures) {
      _state = NetworkCircuitState.open;
      _circuitOpenedAt = DateTime.now();
    }
  }

  BlockReason _block(String code, String message) {
    final reason = BlockReason(
      code: code,
      message: message,
      timestamp: DateTime.now(),
    );
    _blockLog.add(reason);
    // Garder les 100 derniers
    if (_blockLog.length > 100) {
      _blockLog.removeAt(0);
    }
    onBlocked?.call(reason);
    return reason;
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Instancier en singleton dans l'app :
//   final failGuard = FailClosedGuard(
//     onBlocked: (reason) {
//       auditLog.log(SecurityAction.connectionBlocked, reason.toString());
//     },
//   );
//
// Avant TOUTE connexion SSH :
//   final block = failGuard.validateDestination(targetHost);
//   if (block != null) {
//     showErrorDialog(block.message);
//     return; // JAMAIS de fallback
//   }
//   final circuitBlock = await failGuard.checkConnection();
//   if (circuitBlock != null) {
//     showErrorDialog(circuitBlock.message);
//     return; // JAMAIS de fallback
//   }
//
// Ou utiliser le wrapper :
//   final result = await failGuard.executeSecure(
//     destination: targetHost,
//     operation: () => sshConnect(targetHost),
//     onBlockedReturn: (reason) => SshResult.failed(reason.message),
//   );
// =============================================================
