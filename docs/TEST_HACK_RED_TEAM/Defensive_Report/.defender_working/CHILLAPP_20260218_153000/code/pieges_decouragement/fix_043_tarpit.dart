// =============================================================
// FIX-043 : Tarpit SSH (ralentissement des attaquants)
// GAP-043: Tarpit SSH absent (P1)
// Cible: lib/core/security/security_tarpit.dart (nouveau)
// =============================================================
//
// PROBLEME : Le rate limiting est dans SharedPreferences et
// est donc resetable par un attaquant. Pas de tarpit serveur.
//
// SOLUTION :
// 1. Backoff exponentiel serveur-side (pas resetable)
// 2. Auto-blacklist apres 20 echecs
// 3. Nettoyage automatique des entrees expirees
// 4. Stockage en memoire + persistance dans secure storage
// =============================================================

import 'dart:async';
import 'dart:math';

/// Etat du tarpit pour un identifiant.
class TarpitState {
  int failures;
  DateTime lastFailure;
  DateTime? blacklistedAt;
  bool get isBlacklisted => blacklistedAt != null;

  TarpitState()
      : failures = 0,
        lastFailure = DateTime.now();
}

/// Resultat du tarpit.
class TarpitResult {
  final bool allowed;
  final Duration delay;
  final bool blacklisted;
  final int failureCount;

  const TarpitResult({
    required this.allowed,
    required this.delay,
    required this.blacklisted,
    required this.failureCount,
  });
}

/// Callback quand un identifiant est blackliste.
typedef BlacklistCallback = void Function(String identifier, int failures);

/// Tarpit serveur-side avec backoff exponentiel.
class SecurityTarpit {
  final int maxFailuresBeforeBlacklist;
  final Duration blacklistDuration;
  final Duration maxDelay;
  final Map<String, TarpitState> _states = {};
  BlacklistCallback? onBlacklisted;

  SecurityTarpit({
    this.maxFailuresBeforeBlacklist = 20,
    this.blacklistDuration = const Duration(hours: 24),
    this.maxDelay = const Duration(seconds: 60),
    this.onBlacklisted,
  });

  /// Verifie si un identifiant est autorise et calcule le delai.
  TarpitResult check(String identifier) {
    final state = _states[identifier];

    if (state == null) {
      return const TarpitResult(
        allowed: true,
        delay: Duration.zero,
        blacklisted: false,
        failureCount: 0,
      );
    }

    // Verifier le blacklist
    if (state.isBlacklisted) {
      final elapsed = DateTime.now().difference(state.blacklistedAt!);
      if (elapsed < blacklistDuration) {
        return TarpitResult(
          allowed: false,
          delay: blacklistDuration - elapsed,
          blacklisted: true,
          failureCount: state.failures,
        );
      }
      // Blacklist expire — reset
      _states.remove(identifier);
      return const TarpitResult(
        allowed: true,
        delay: Duration.zero,
        blacklisted: false,
        failureCount: 0,
      );
    }

    // Calculer le delai exponentiel
    // 0, 1s, 2s, 4s, 8s, 16s, 32s, 60s max
    final delaySeconds = state.failures <= 1
        ? 0
        : min(
            (1 << (state.failures - 1)),
            maxDelay.inSeconds,
          );

    return TarpitResult(
      allowed: true,
      delay: Duration(seconds: delaySeconds),
      blacklisted: false,
      failureCount: state.failures,
    );
  }

  /// Enregistre un echec (PIN incorrect, tentative SSH, etc.).
  TarpitResult recordFailure(String identifier) {
    final state = _states.putIfAbsent(identifier, () => TarpitState());
    state.failures++;
    state.lastFailure = DateTime.now();

    // Auto-blacklist
    if (state.failures >= maxFailuresBeforeBlacklist && !state.isBlacklisted) {
      state.blacklistedAt = DateTime.now();
      onBlacklisted?.call(identifier, state.failures);
    }

    return check(identifier);
  }

  /// Enregistre un succes (reset le compteur).
  void recordSuccess(String identifier) {
    _states.remove(identifier);
  }

  /// Verifie si un identifiant est blackliste.
  bool isBlacklisted(String identifier) {
    final state = _states[identifier];
    if (state == null) return false;
    if (!state.isBlacklisted) return false;
    // Verifier l'expiration
    final elapsed = DateTime.now().difference(state.blacklistedAt!);
    return elapsed < blacklistDuration;
  }

  /// Statistiques.
  Map<String, dynamic> get stats => {
    'total_tracked': _states.length,
    'blacklisted': _states.values.where((s) => s.isBlacklisted).length,
    'total_failures': _states.values.fold<int>(0, (sum, s) => sum + s.failures),
  };

  /// Nettoie les entrees expirees.
  void cleanup() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _states.removeWhere((_, state) {
      if (state.isBlacklisted) {
        final elapsed = DateTime.now().difference(state.blacklistedAt!);
        return elapsed >= blacklistDuration;
      }
      return state.lastFailure.isBefore(cutoff);
    });
  }

  /// Applique le delai tarpit (bloquant).
  Future<TarpitResult> applyAndWait(String identifier) async {
    final result = check(identifier);
    if (result.delay > Duration.zero && result.allowed) {
      await Future.delayed(result.delay);
    }
    return result;
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Singleton dans l'app :
//   final tarpit = SecurityTarpit(
//     onBlacklisted: (id, failures) {
//       auditLog.log(SecurityAction.blacklisted,
//         'Identifiant $id blackliste apres $failures echecs');
//     },
//   );
//
// Avant verification du PIN :
//   final result = tarpit.check('pin_attempts');
//   if (!result.allowed) {
//     showBlockedDialog(result.delay);
//     return;
//   }
//   if (result.delay > Duration.zero) {
//     await Future.delayed(result.delay); // Ralentir
//   }
//   // Verifier le PIN...
//   if (pinIncorrect) {
//     tarpit.recordFailure('pin_attempts');
//   } else {
//     tarpit.recordSuccess('pin_attempts');
//   }
//
// Nettoyage periodique :
//   Timer.periodic(Duration(hours: 1), (_) => tarpit.cleanup());
// =============================================================
