// =============================================================
// FIX-005 : Sealed classes pour machines a etats securite
// GAP-005 : Pas de sealed classes pour etats de securite
// Cible : lib/features/lock/lock_provider.dart,
//         lib/features/tailscale/tailscale_provider.dart
// =============================================================
//
// PROBLEME : Les etats de securite sont geres par des bool/enum
// simples. Le compilateur ne force pas le traitement de tous
// les cas possibles. Un etat non gere peut laisser l'app dans
// un etat de securite ambigu (ni verrouille ni deverrouille).
//
// SOLUTION : Sealed classes Dart 3 avec exhaustivite forcee.
// Le compilateur garantit que chaque etat est traite.
// =============================================================

/// Machine a etats pour le verrouillage par PIN.
/// Le compilateur force le switch exhaustif.
sealed class LockSecurityState {}

/// PIN non configure — pas de protection.
class LockDisabled extends LockSecurityState {}

/// PIN configure, app verrouille, attend la saisie.
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

/// PIN verifie, app deverrouille, acces autorise.
class LockUnlocked extends LockSecurityState {}

/// Compromission detectee — acces refuse, kill switch potentiel.
class LockCompromised extends LockSecurityState {
  final String reason;
  LockCompromised(this.reason);
}

// ---

/// Machine a etats pour la connexion daemon Tailscale.
/// Chaque etat est un cas distinct que le code DOIT traiter.
sealed class DaemonConnectionState {}

/// Daemon non demarre.
class DaemonStopped extends DaemonConnectionState {}

/// Daemon en cours de demarrage (verification d'integrite).
class DaemonStarting extends DaemonConnectionState {
  final String binaryPath;
  DaemonStarting(this.binaryPath);
}

/// Daemon demarre et IPC connecte.
class DaemonConnected extends DaemonConnectionState {
  final int pid;
  DaemonConnected(this.pid);
}

/// Daemon en erreur (crash, timeout, integrite echouee).
class DaemonError extends DaemonConnectionState {
  final String error;
  final bool integrityFailed;
  DaemonError(this.error, {this.integrityFailed = false});
}

// ---

/// Exemple d'utilisation avec switch exhaustif :
///
/// ```dart
/// String handleLockState(LockSecurityState state) {
///   return switch (state) {
///     LockDisabled()   => 'PIN non configure',
///     LockActive()     => 'En attente du PIN (${state.failedAttempts} echecs)',
///     LockUnlocked()   => 'Deverrouille',
///     LockCompromised() => 'COMPROMIS: ${state.reason}',
///   };
///   // Si un nouvel etat est ajoute, le compilateur FORCE
///   // l'ajout d'un case ici. Pas d'oubli possible.
/// }
/// ```

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Remplacer LockState dans lock_provider.dart par
//    LockSecurityState sealed class
//
// 2. Adapter le LockNotifier pour utiliser les sealed classes :
//    state = LockActive(failedAttempts: newAttempts, ...);
//    au lieu de :
//    state = state.copyWith(failedAttempts: newAttempts, ...);
//
// 3. Dans tous les widgets qui lisent lockProvider,
//    utiliser switch exhaustif sur LockSecurityState
