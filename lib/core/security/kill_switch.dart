// FIX-045/055 — Kill Switch multi-couche résistant aux agents IA
// Efface les clés SSH, ferme les sessions, déconnecte Tailscale,
// et supprime les données sensibles en cas de déclenchement.
import 'dart:io';
import 'dart:async';

/// Raisons possibles de déclenchement du kill switch.
enum KillReason {
  userTriggered,
  heartbeatTimeout,
  canaryTriggered,
  bruteForceDetected,
  aiAgentDetected,
  logTamperingDetected,
}

/// Résultat de l'exécution du kill switch.
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

/// Signature du callback appelé lors du déclenchement.
typedef KillSwitchCallback = void Function(KillReason reason, String detail);

/// Kill switch multi-couche.
///
/// Conçu pour résister aux agents IA : chaque étape est indépendante
/// (une erreur n'arrête pas les suivantes) et l'effacement des clés SSH
/// est fait octet par octet avant suppression pour éviter la récupération.
class KillSwitch {
  KillSwitchCallback? onTrigger;
  final String sshDir;
  final String secureStoragePath;

  KillSwitch({
    this.onTrigger,
    String? sshDir,
    String? secureStoragePath,
  })  : sshDir = sshDir ??
            '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''}/.ssh',
        secureStoragePath = secureStoragePath ?? '';

  /// Exécute le kill switch.
  ///
  /// Si [skipConfirmation] est false, appelle [pinConfirmation] et annule
  /// si la confirmation est refusée. Toutes les étapes sont exécutées même
  /// en cas d'erreur partielle ; les erreurs sont collectées dans le résultat.
  Future<KillSwitchResult> execute({
    required KillReason reason,
    required Future<bool> Function() pinConfirmation,
    bool skipConfirmation = false,
  }) async {
    final actions = <String>[];
    final errors = <String>[];

    if (!skipConfirmation) {
      final confirmed = await pinConfirmation();
      if (!confirmed) {
        return const KillSwitchResult(
          success: false,
          actionsPerformed: [],
          errors: ['Confirmation PIN refusee'],
        );
      }
    }

    onTrigger?.call(reason, 'Kill switch execute: ${reason.name}');

    // Chaque étape est indépendante pour garantir que la suite s'exécute
    // même si une étape échoue (résilience face aux erreurs partielles).
    try {
      await wipeSSHKeys();
      actions.add('Cles SSH effacees');
    } catch (e) {
      errors.add('Erreur wipe SSH: $e');
    }

    try {
      await closeAllSessions();
      actions.add('Sessions fermees');
    } catch (e) {
      errors.add('Erreur fermeture sessions: $e');
    }

    try {
      await disconnectTailscale();
      actions.add('Tailscale deconnecte');
    } catch (e) {
      errors.add('Erreur deconnexion Tailscale: $e');
    }

    try {
      await clearSensitiveData();
      actions.add('Donnees sensibles effacees');
    } catch (e) {
      errors.add('Erreur effacement donnees: $e');
    }

    return KillSwitchResult(
      success: errors.isEmpty,
      actionsPerformed: actions,
      errors: errors,
    );
  }

  /// Efface les clés SSH privées.
  ///
  /// Surcharger cette méthode dans les tests pour éviter les I/O réels.
  /// Écrase les octets à zéro avant suppression (anti-récupération forensique).
  Future<void> wipeSSHKeys() async {
    final dir = Directory(sshDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if ((name.startsWith('id_') && !name.endsWith('.pub')) ||
            name.contains('chillapp') ||
            name.contains('canary') ||
            name.endsWith('.old')) {
          final length = await entity.length();
          if (length > 0) {
            await entity.writeAsBytes(List.filled(length, 0));
          }
          await entity.delete();
        }
      }
    }
  }

  /// Ferme toutes les sessions SSH et Tailscale actives.
  ///
  /// Surcharger cette méthode dans les tests.
  Future<void> closeAllSessions() async {
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-Command',
        'Get-Process -Name ssh,chill-tailscale -ErrorAction SilentlyContinue | Stop-Process -Force',
      ]);
    } else {
      await Process.run('pkill', ['-f', 'chill-tailscale']);
    }
  }

  /// Déconnecte et déconnecte Tailscale.
  ///
  /// Surcharger cette méthode dans les tests.
  Future<void> disconnectTailscale() async {
    await Process.run('tailscale', ['down']);
    await Process.run('tailscale', ['logout']);
  }

  /// Efface les données sensibles du trousseau système.
  ///
  /// Supporte Linux (secret-tool) et macOS (security).
  /// Surcharger cette méthode dans les tests.
  Future<void> clearSensitiveData() async {
    if (Platform.isLinux) {
      for (final key in [
        'pin_hash',
        'pin_salt',
        'rate_limit',
        'audit_key',
        'ipc_key'
      ]) {
        await Process.run(
            'secret-tool', ['clear', 'service', 'chillapp', 'key', key]);
      }
    } else if (Platform.isMacOS) {
      for (final key in [
        'pin_hash',
        'pin_salt',
        'rate_limit',
        'audit_key',
        'ipc_key'
      ]) {
        await Process.run('security', [
          'delete-generic-password',
          '-s',
          'com.chill.chillapp',
          '-a',
          key,
        ]);
      }
    }
  }
}

/// Watchdog qui déclenche automatiquement le kill switch si le battement
/// de cœur s'arrête trop longtemps (détection de gel ou d'agent IA).
class KillSwitchWatchdog {
  final Duration heartbeatInterval;
  final Duration maxMissedHeartbeats;
  final KillSwitch killSwitch;
  Timer? _timer;
  DateTime _lastHeartbeat;

  /// Vrai si un heartbeat initial a été fourni au constructeur.
  /// Dans ce cas, start() ne réinitialise pas _lastHeartbeat.
  final bool _hasInitialHeartbeat;

  bool _triggered = false;

  /// Nombre de vérifications consécutives en dépassement avant déclenchement.
  /// Évite les faux positifs (gel UI temporaire, charge CPU).
  int _consecutiveMisses = 0;
  static const int requiredConsecutiveMisses = 3;

  KillSwitchWatchdog({
    required this.killSwitch,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.maxMissedHeartbeats = const Duration(minutes: 2),
    /// Uniquement pour les tests : permet de simuler un heartbeat passé.
    /// Quand fourni, start() ne réinitialise pas _lastHeartbeat.
    DateTime? initialLastHeartbeat,
  })  : _lastHeartbeat = initialLastHeartbeat ?? DateTime.now(),
        _hasInitialHeartbeat = initialLastHeartbeat != null;

  /// Indique si le watchdog est en cours d'exécution.
  bool get isRunning => _timer != null;

  /// Indique si le kill switch a déjà été déclenché par ce watchdog.
  bool get hasTriggered => _triggered;

  /// Horodatage du dernier battement de cœur reçu.
  DateTime get lastHeartbeat => _lastHeartbeat;

  /// Démarre le watchdog. Réinitialise l'état de déclenchement.
  /// Si [initialLastHeartbeat] a été fourni au constructeur,
  /// _lastHeartbeat est préservé (utile pour les tests).
  void start() {
    if (!_hasInitialHeartbeat) {
      _lastHeartbeat = DateTime.now();
    }
    _triggered = false;
    _timer = Timer.periodic(heartbeatInterval, (_) => check());
  }

  /// Enregistre un battement de cœur (l'app est vivante).
  void heartbeat() {
    _lastHeartbeat = DateTime.now();
    _consecutiveMisses = 0;
  }

  /// Arrête le watchdog proprement.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Vérifie si le délai maximal sans battement de cœur est dépassé.
  ///
  /// Public pour les tests : permet d'appeler manuellement sans timer.
  void check() {
    final elapsed = DateTime.now().difference(_lastHeartbeat);
    if (elapsed > maxMissedHeartbeats && !_triggered) {
      _consecutiveMisses++;
      if (_consecutiveMisses >= requiredConsecutiveMisses) {
        _triggered = true;
        killSwitch.execute(
          reason: KillReason.heartbeatTimeout,
          pinConfirmation: () async => true,
          skipConfirmation: true,
        );
        stop();
      }
    } else if (elapsed <= maxMissedHeartbeats) {
      _consecutiveMisses = 0;
    }
  }
}
