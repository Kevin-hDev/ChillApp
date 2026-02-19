// =============================================================
// TEST FIX-043 : Security Tarpit
// Verification du backoff exponentiel et du blacklisting
// =============================================================

import 'dart:math';
import 'package:test/test.dart';

// Reproduction de TarpitState pour les tests
class TarpitState {
  int failures;
  DateTime lastFailure;
  DateTime? blacklistedAt;
  bool get isBlacklisted => blacklistedAt != null;

  TarpitState()
      : failures = 0,
        lastFailure = DateTime.now();
}

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

class SecurityTarpit {
  final int maxFailuresBeforeBlacklist;
  final Duration blacklistDuration;
  final Duration maxDelay;
  final Map<String, TarpitState> _states = {};

  SecurityTarpit({
    this.maxFailuresBeforeBlacklist = 20,
    this.blacklistDuration = const Duration(hours: 24),
    this.maxDelay = const Duration(seconds: 60),
  });

  TarpitResult check(String identifier) {
    final state = _states[identifier];
    if (state == null) {
      return const TarpitResult(
        allowed: true, delay: Duration.zero,
        blacklisted: false, failureCount: 0,
      );
    }
    if (state.isBlacklisted) {
      final elapsed = DateTime.now().difference(state.blacklistedAt!);
      if (elapsed < blacklistDuration) {
        return TarpitResult(
          allowed: false, delay: blacklistDuration - elapsed,
          blacklisted: true, failureCount: state.failures,
        );
      }
      _states.remove(identifier);
      return const TarpitResult(
        allowed: true, delay: Duration.zero,
        blacklisted: false, failureCount: 0,
      );
    }
    final delaySeconds = state.failures <= 1
        ? 0
        : min((1 << (state.failures - 1)), maxDelay.inSeconds);
    return TarpitResult(
      allowed: true, delay: Duration(seconds: delaySeconds),
      blacklisted: false, failureCount: state.failures,
    );
  }

  TarpitResult recordFailure(String identifier) {
    final state = _states.putIfAbsent(identifier, () => TarpitState());
    state.failures++;
    state.lastFailure = DateTime.now();
    if (state.failures >= maxFailuresBeforeBlacklist && !state.isBlacklisted) {
      state.blacklistedAt = DateTime.now();
    }
    return check(identifier);
  }

  void recordSuccess(String identifier) {
    _states.remove(identifier);
  }

  bool isBlacklisted(String identifier) {
    final state = _states[identifier];
    if (state == null) return false;
    if (!state.isBlacklisted) return false;
    final elapsed = DateTime.now().difference(state.blacklistedAt!);
    return elapsed < blacklistDuration;
  }
}

void main() {
  group('SecurityTarpit — Backoff exponentiel', () {
    test('premier check sans echec = autorise, delai zero', () {
      final tarpit = SecurityTarpit();
      final result = tarpit.check('test_user');
      expect(result.allowed, isTrue);
      expect(result.delay, Duration.zero);
      expect(result.blacklisted, isFalse);
      expect(result.failureCount, 0);
    });

    test('premier echec = delai zero (grace)', () {
      final tarpit = SecurityTarpit();
      final result = tarpit.recordFailure('test_user');
      expect(result.allowed, isTrue);
      expect(result.delay, Duration.zero);
      expect(result.failureCount, 1);
    });

    test('echec #2 = delai 2 secondes', () {
      final tarpit = SecurityTarpit();
      tarpit.recordFailure('user');
      final result = tarpit.recordFailure('user');
      expect(result.delay.inSeconds, 2);
    });

    test('echec #3 = delai 4 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 3; i++) tarpit.recordFailure('user');
      final result = tarpit.check('user');
      expect(result.delay.inSeconds, 4);
    });

    test('echec #5 = delai 16 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 5; i++) tarpit.recordFailure('user');
      final result = tarpit.check('user');
      expect(result.delay.inSeconds, 16);
    });

    test('delai ne depasse jamais maxDelay (60s)', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 15; i++) tarpit.recordFailure('user');
      final result = tarpit.check('user');
      expect(result.delay.inSeconds, lessThanOrEqualTo(60));
    });

    test('delai croissant est exponentiel', () {
      final tarpit = SecurityTarpit();
      final delays = <int>[];
      for (int i = 0; i < 8; i++) {
        tarpit.recordFailure('user');
        delays.add(tarpit.check('user').delay.inSeconds);
      }
      // Les delais doivent etre croissants ou plafonnes
      for (int i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThanOrEqualTo(delays[i - 1]));
      }
    });
  });

  group('SecurityTarpit — Auto-blacklist', () {
    test('blacklist apres 20 echecs par defaut', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 20; i++) {
        tarpit.recordFailure('brute');
      }
      expect(tarpit.isBlacklisted('brute'), isTrue);
    });

    test('blacklist bloque toutes les requetes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 20; i++) tarpit.recordFailure('brute');
      final result = tarpit.check('brute');
      expect(result.allowed, isFalse);
      expect(result.blacklisted, isTrue);
    });

    test('19 echecs ne blacklistent pas', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 19; i++) tarpit.recordFailure('test');
      expect(tarpit.isBlacklisted('test'), isFalse);
    });

    test('seuil configurable', () {
      final tarpit = SecurityTarpit(maxFailuresBeforeBlacklist: 5);
      for (int i = 0; i < 5; i++) tarpit.recordFailure('test');
      expect(tarpit.isBlacklisted('test'), isTrue);
    });
  });

  group('SecurityTarpit — Succes et reset', () {
    test('succes reset le compteur', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 5; i++) tarpit.recordFailure('user');
      tarpit.recordSuccess('user');
      final result = tarpit.check('user');
      expect(result.failureCount, 0);
      expect(result.delay, Duration.zero);
    });

    test('identifiants differents sont independants', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 10; i++) tarpit.recordFailure('user_a');
      tarpit.recordFailure('user_b');
      expect(tarpit.check('user_a').failureCount, 10);
      expect(tarpit.check('user_b').failureCount, 1);
    });
  });
}
