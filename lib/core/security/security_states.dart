// =============================================================
// FIX-005 : Sealed classes pour machines à états sécurité
// GAP-005 : Pas de sealed classes pour états de sécurité
// Cible : lib/features/lock/lock_provider.dart,
//         lib/features/tailscale/tailscale_provider.dart
// =============================================================
//
// PROBLÈME : Les états de sécurité sont gérés par des bool/enum
// simples. Le compilateur ne force pas le traitement de tous
// les cas possibles. Un état non géré peut laisser l'app dans
// un état de sécurité ambigu (ni verrouillé ni déverrouillé).
//
// SOLUTION : Sealed classes Dart 3 avec exhaustivité forcée.
// Le compilateur garantit que chaque état est traité.
// =============================================================

/// Machine à états pour le verrouillage par PIN.
/// Le compilateur force le switch exhaustif.
sealed class LockSecurityState {}

/// PIN non configuré — pas de protection.
class LockDisabled extends LockSecurityState {}

/// PIN configuré, app verrouillée, attend la saisie.
class LockActive extends LockSecurityState {
  final int failedAttempts;
  final DateTime? lockedUntil;

  LockActive({
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  bool get isTemporarilyLocked =>
      lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  Duration? get remainingLockTime {
    if (lockedUntil == null) return null;
    final remaining = lockedUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }
}

/// PIN vérifié, app déverrouillée, accès autorisé.
class LockUnlocked extends LockSecurityState {}

/// Compromission détectée — accès refusé, kill switch potentiel.
class LockCompromised extends LockSecurityState {
  final String reason;
  LockCompromised(this.reason);
}

// ---

/// Machine à états pour la connexion daemon Tailscale.
/// Chaque état est un cas distinct que le code DOIT traiter.
sealed class DaemonConnectionState {}

/// Daemon non démarré.
class DaemonStopped extends DaemonConnectionState {}

/// Daemon en cours de démarrage (vérification d'intégrité).
class DaemonStarting extends DaemonConnectionState {
  final String binaryPath;
  DaemonStarting(this.binaryPath);
}

/// Daemon démarré et IPC connecté.
class DaemonConnected extends DaemonConnectionState {
  final int pid;
  DaemonConnected(this.pid);
}

/// Daemon en erreur (crash, timeout, intégrité échouée).
class DaemonError extends DaemonConnectionState {
  final String error;
  final bool integrityFailed;
  DaemonError(this.error, {this.integrityFailed = false});
}
