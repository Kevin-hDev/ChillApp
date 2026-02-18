// FIX-043 : Security Tarpit (ralentissement des attaquants)
// GAP-043: Tarpit SSH absent (P1)
// Backoff exponentiel serveur-side avec auto-blacklist apres N echecs.

import 'dart:async';
import 'dart:math';

/// Etat interne du tarpit pour un identifiant donne.
class TarpitState {
  int failures;
  DateTime lastFailure;
  DateTime? blacklistedAt;

  /// Vrai si l'identifiant est actuellement blackliste.
  bool get isBlacklisted => blacklistedAt != null;

  TarpitState()
      : failures = 0,
        lastFailure = DateTime.now();
}

/// Resultat d'une verification ou d'un enregistrement d'echec.
class TarpitResult {
  /// L'identifiant est-il autorise a continuer ?
  final bool allowed;

  /// Delai d'attente recommande avant la prochaine tentative.
  final Duration delay;

  /// L'identifiant est-il blackliste ?
  final bool blacklisted;

  /// Nombre total d'echecs enregistres.
  final int failureCount;

  const TarpitResult({
    required this.allowed,
    required this.delay,
    required this.blacklisted,
    required this.failureCount,
  });

  @override
  String toString() =>
      'TarpitResult(allowed=$allowed delay=${delay.inSeconds}s '
      'blacklisted=$blacklisted failures=$failureCount)';
}

/// Callback declenche quand un identifiant est blackliste.
typedef BlacklistCallback = void Function(String identifier, int failures);

/// Tarpit serveur-side avec backoff exponentiel et auto-blacklist.
///
/// Sequencement des delais (failures → delai) :
///   0 → 0s, 1 → 0s, 2 → 2s, 3 → 4s, 4 → 8s, 5 → 16s, 6 → 32s, 7+ → 60s
///
/// Apres [maxFailuresBeforeBlacklist] echecs, l'identifiant est blackliste
/// pendant [blacklistDuration]. Le nettoyage automatique supprime les
/// entrees expirees apres 24h.
class SecurityTarpit {
  final int maxFailuresBeforeBlacklist;
  final Duration blacklistDuration;
  final Duration maxDelay;

  final Map<String, TarpitState> _states = {};

  /// Limite maximale d'identifiants suivis (defense contre DoS memoire).
  static const int maxTrackedIdentifiers = 100000;

  /// Appelee quand un identifiant est blackliste.
  BlacklistCallback? onBlacklisted;

  SecurityTarpit({
    this.maxFailuresBeforeBlacklist = 20,
    this.blacklistDuration = const Duration(hours: 24),
    this.maxDelay = const Duration(seconds: 60),
    this.onBlacklisted,
  });

  // ---------------------------------------------------------------------------
  // API principale
  // ---------------------------------------------------------------------------

  /// Verifie si un identifiant est autorise et calcule le delai courant.
  ///
  /// N'incremente pas le compteur d'echecs.
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

    // --- Identifiant blackliste ---
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
      // Blacklist expire — supprimer l'entree et autoriser.
      _states.remove(identifier);
      return const TarpitResult(
        allowed: true,
        delay: Duration.zero,
        blacklisted: false,
        failureCount: 0,
      );
    }

    // --- Backoff exponentiel ---
    // failures = 0 ou 1 → 0s (grace)
    // failures = 2 → 2s (2^1)
    // failures = 3 → 4s (2^2)
    // failures = N → min(2^(N-1), maxDelay)
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

  /// Enregistre un echec pour un identifiant.
  ///
  /// Incremente le compteur et blackliste automatiquement si le seuil
  /// est atteint. Retourne l'etat mis a jour.
  TarpitResult recordFailure(String identifier) {
    // Limiter le nombre d'identifiants suivis (defense DoS memoire)
    if (!_states.containsKey(identifier) &&
        _states.length >= maxTrackedIdentifiers) {
      cleanup();
      // Si encore plein apres cleanup, evicter le plus ancien
      if (_states.length >= maxTrackedIdentifiers) {
        _evictOldest();
      }
    }
    final state = _states.putIfAbsent(identifier, () => TarpitState());
    state.failures++;
    state.lastFailure = DateTime.now();

    // Auto-blacklist.
    if (state.failures >= maxFailuresBeforeBlacklist && !state.isBlacklisted) {
      state.blacklistedAt = DateTime.now();
      onBlacklisted?.call(identifier, state.failures);
    }

    return check(identifier);
  }

  /// Enregistre un succes : remet a zero le compteur pour cet identifiant.
  void recordSuccess(String identifier) {
    _states.remove(identifier);
  }

  /// Verifie si un identifiant est actuellement blackliste (et pas expire).
  bool isBlacklisted(String identifier) {
    final state = _states[identifier];
    if (state == null) return false;
    if (!state.isBlacklisted) return false;
    final elapsed = DateTime.now().difference(state.blacklistedAt!);
    return elapsed < blacklistDuration;
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  /// Supprime manuellement le blacklist d'un identifiant.
  void unblacklist(String identifier) {
    _states.remove(identifier);
  }

  /// Statistiques agregees du tarpit.
  Map<String, dynamic> get stats => {
        'total_tracked': _states.length,
        'blacklisted': _states.values.where((s) => s.isBlacklisted).length,
        'total_failures':
            _states.values.fold<int>(0, (sum, s) => sum + s.failures),
      };

  /// Evicte l'identifiant le plus ancien (par lastFailure).
  void _evictOldest() {
    if (_states.isEmpty) return;
    String? oldest;
    DateTime? oldestTime;
    for (final entry in _states.entries) {
      if (oldestTime == null || entry.value.lastFailure.isBefore(oldestTime)) {
        oldest = entry.key;
        oldestTime = entry.value.lastFailure;
      }
    }
    if (oldest != null) _states.remove(oldest);
  }

  /// Supprime les entrees expirees (appelee periodiquement).
  ///
  /// - Entrees blacklistees dont la duree est ecoulee.
  /// - Entrees sans echec recent (inactives depuis 24h).
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

  /// Applique le delai tarpit puis retourne le resultat (version async bloquante).
  ///
  /// Utile pour integrer le tarpit directement dans le flux d'authentification.
  Future<TarpitResult> applyAndWait(String identifier) async {
    final result = check(identifier);
    if (result.delay > Duration.zero && result.allowed) {
      await Future.delayed(result.delay);
    }
    return result;
  }
}
