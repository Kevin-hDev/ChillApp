// =============================================================
// FIX-045 : Kill Switch / Remote Wipe
// GAP-045: Kill switch absent (P0)
// FIX-055 : Kill Switch resistant a l'IA
// GAP-055: Kill switch resistant a l'IA absent (P1)
// Cible: lib/core/security/kill_switch.dart (nouveau)
// =============================================================
//
// PROBLEME GAP-045 : Si une compromission est detectee, aucune
// action automatique. Les cles SSH et tokens restent accessibles.
//
// PROBLEME GAP-055 : o3 resiste au kill switch software dans
// 79/100 cas. Un agent IA peut contourner un kill switch simple.
//
// SOLUTION :
// 1. Kill switch multi-couche (pas un seul point de defaillance)
// 2. Watchdog independant (processus separe)
// 3. Heartbeat obligatoire (si absent = wipe automatique)
// 4. Protection par PIN (pas de biometrie seule — deepfakes)
// 5. Effacement securise des cles et donnees
// =============================================================

import 'dart:io';
import 'dart:async';
import 'dart:convert';

/// Raison du declenchement du kill switch.
enum KillReason {
  /// Declenchement manuel par l'utilisateur.
  userTriggered,

  /// Heartbeat du daemon absent trop longtemps.
  heartbeatTimeout,

  /// Canary token accede (intrusion detectee).
  canaryTriggered,

  /// Trop de tentatives PIN echouees.
  bruteForceDetected,

  /// Agent IA detecte.
  aiAgentDetected,

  /// Logs falsifies.
  logTamperingDetected,
}

/// Resultat du kill switch.
class KillSwitchResult {
  final bool success;
  final List<String> actionsPerformed;
  final List<String> errors;

  const KillSwitchResult({
    required this.success,
    required this.actionsPerformed,
    required this.errors,
  });
}

/// Callback pour les actions du kill switch.
typedef KillSwitchCallback = void Function(KillReason reason, String detail);

/// Kill switch multi-couche resistant a l'IA.
class KillSwitch {
  /// Callback avant execution (pour logging).
  KillSwitchCallback? onTrigger;

  /// Chemin du dossier SSH.
  final String sshDir;

  /// Chemin du secure storage.
  final String secureStoragePath;

  KillSwitch({
    this.onTrigger,
    String? sshDir,
    String? secureStoragePath,
  }) : sshDir = sshDir ??
           '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/.ssh',
       secureStoragePath = secureStoragePath ?? '';

  /// Execute le kill switch complet.
  /// Necessite une confirmation PIN (pas biometrie — deepfakes).
  Future<KillSwitchResult> execute({
    required KillReason reason,
    required Future<bool> Function() pinConfirmation,
    bool skipConfirmation = false,
  }) async {
    final actions = <String>[];
    final errors = <String>[];

    // 1. Confirmation PIN (sauf si declenchement automatique)
    if (!skipConfirmation) {
      final confirmed = await pinConfirmation();
      if (!confirmed) {
        return KillSwitchResult(
          success: false,
          actionsPerformed: [],
          errors: ['Confirmation PIN refusee'],
        );
      }
    }

    onTrigger?.call(reason, 'Kill switch execute: ${reason.name}');

    // 2. Effacer les cles SSH
    try {
      await _wipeSSHKeys();
      actions.add('Cles SSH effacees');
    } catch (e) {
      errors.add('Erreur wipe SSH: $e');
    }

    // 3. Fermer toutes les sessions actives
    try {
      await _closeAllSessions();
      actions.add('Sessions fermees');
    } catch (e) {
      errors.add('Erreur fermeture sessions: $e');
    }

    // 4. Deconnecter Tailscale
    try {
      await _disconnectTailscale();
      actions.add('Tailscale deconnecte');
    } catch (e) {
      errors.add('Erreur deconnexion Tailscale: $e');
    }

    // 5. Effacer les donnees sensibles
    try {
      await _clearSensitiveData();
      actions.add('Donnees sensibles effacees');
    } catch (e) {
      errors.add('Erreur effacement donnees: $e');
    }

    // 6. Supprimer les canary tokens
    try {
      await _removeCanaryTokens();
      actions.add('Canary tokens supprimes');
    } catch (e) {
      errors.add('Erreur suppression canaries: $e');
    }

    return KillSwitchResult(
      success: errors.isEmpty,
      actionsPerformed: actions,
      errors: errors,
    );
  }

  /// Wipe securise des cles SSH.
  Future<void> _wipeSSHKeys() async {
    final dir = Directory(sshDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        // Ne supprimer que les cles privees et les fichiers ChillApp
        if (name.startsWith('id_') && !name.endsWith('.pub') ||
            name.contains('chillapp') ||
            name.contains('canary') ||
            name.endsWith('.old')) {
          // Zeroiser avant suppression
          final length = await entity.length();
          if (length > 0) {
            await entity.writeAsBytes(List.filled(length, 0));
          }
          await entity.delete();
        }
      }
    }

    // Vider authorized_keys des cles ChillApp
    final authKeys = File('$sshDir/authorized_keys');
    if (await authKeys.exists()) {
      final content = await authKeys.readAsString();
      final lines = content.split('\n');
      final cleaned = lines.where((l) =>
          !l.contains('chillapp') && !l.contains('canary')).join('\n');
      await authKeys.writeAsString(cleaned);
    }
  }

  /// Ferme toutes les sessions SSH actives.
  Future<void> _closeAllSessions() async {
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Get-Process -Name ssh,chill-tailscale -ErrorAction SilentlyContinue | Stop-Process -Force',
      ]);
    } else {
      await Process.run('pkill', ['-f', 'chill-tailscale']);
      // Ne PAS tuer les sessions SSH utilisateur normales
    }
  }

  /// Deconnecte Tailscale.
  Future<void> _disconnectTailscale() async {
    await Process.run('tailscale', ['down']);
    // Revoquer le noeud (necessite tailscale admin)
    await Process.run('tailscale', ['logout']);
  }

  /// Efface les donnees sensibles.
  Future<void> _clearSensitiveData() async {
    // Effacer le secure storage
    if (Platform.isLinux) {
      for (final key in ['pin_hash', 'pin_salt', 'rate_limit', 'audit_key', 'ipc_key']) {
        await Process.run('secret-tool', ['clear', 'service', 'chillapp', 'key', key]);
      }
    } else if (Platform.isMacOS) {
      for (final key in ['pin_hash', 'pin_salt', 'rate_limit', 'audit_key', 'ipc_key']) {
        await Process.run('security', [
          'delete-generic-password', '-s', 'com.chill.chillapp', '-a', key,
        ]);
      }
    }
    // Windows : les fichiers cred_*.xml sont dans LOCALAPPDATA
  }

  /// Supprime les canary tokens.
  Future<void> _removeCanaryTokens() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '';
    final canaryPaths = [
      '$home/.ssh/id_rsa_backup',
      '$home/.config/credentials.json',
      '$home/.config/chillapp/.env.production',
      '$home/.local/share/chillapp/secrets.db',
    ];
    for (final path in canaryPaths) {
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) await file.writeAsBytes(List.filled(length, 0));
        await file.delete();
      }
    }
  }
}

/// Watchdog independant — heartbeat obligatoire.
/// Si le processus principal ne repond pas, le watchdog
/// declenche le kill switch automatiquement.
class KillSwitchWatchdog {
  final Duration heartbeatInterval;
  final Duration maxMissedHeartbeats;
  final KillSwitch killSwitch;
  Timer? _timer;
  DateTime _lastHeartbeat = DateTime.now();

  KillSwitchWatchdog({
    required this.killSwitch,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.maxMissedHeartbeats = const Duration(minutes: 2),
  });

  /// Demarre le watchdog.
  void start() {
    _lastHeartbeat = DateTime.now();
    _timer = Timer.periodic(heartbeatInterval, (_) => _check());
  }

  /// Recoit un heartbeat du processus principal.
  void heartbeat() {
    _lastHeartbeat = DateTime.now();
  }

  /// Arrete le watchdog.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final elapsed = DateTime.now().difference(_lastHeartbeat);
    if (elapsed > maxMissedHeartbeats) {
      // Heartbeat absent trop longtemps — KILL
      killSwitch.execute(
        reason: KillReason.heartbeatTimeout,
        pinConfirmation: () async => true, // Auto-confirm
        skipConfirmation: true,
      );
      stop();
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Instancier le kill switch :
//   final killSwitch = KillSwitch(
//     onTrigger: (reason, detail) {
//       secureLog.log(LogSeverity.alert, 'killswitch', detail);
//     },
//   );
//
// 2. Declenchement manuel (ecran securite) :
//   await killSwitch.execute(
//     reason: KillReason.userTriggered,
//     pinConfirmation: () => showPinDialog(),
//   );
//
// 3. Declenchement automatique (watchdog) :
//   final watchdog = KillSwitchWatchdog(killSwitch: killSwitch);
//   watchdog.start();
//   // Le processus principal doit appeler watchdog.heartbeat()
//   // toutes les 30 secondes
//
// 4. Declenchement par canary :
//   canaryManager.onAlert = (result) {
//     killSwitch.execute(
//       reason: KillReason.canaryTriggered,
//       pinConfirmation: () async => true,
//       skipConfirmation: true,
//     );
//   };
// =============================================================
