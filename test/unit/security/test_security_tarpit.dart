// Tests unitaires pour FIX-043 — Security Tarpit
// Lance avec : flutter test test/unit/security/test_security_tarpit.dart
//
// Verifie le backoff exponentiel, le blacklisting automatique, le reset
// et la gestion multi-identifiants. Aucun I/O.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/security_tarpit.dart';

void main() {
  // ===========================================================================
  // TarpitState
  // ===========================================================================

  group('TarpitState — initialisation', () {
    test('failures demarre a 0', () {
      final state = TarpitState();
      expect(state.failures, 0);
    });

    test('isBlacklisted est false a la creation', () {
      final state = TarpitState();
      expect(state.isBlacklisted, isFalse);
    });

    test('blacklistedAt est null a la creation', () {
      final state = TarpitState();
      expect(state.blacklistedAt, isNull);
    });

    test('isBlacklisted devient true quand blacklistedAt est defini', () {
      final state = TarpitState();
      state.blacklistedAt = DateTime.now();
      expect(state.isBlacklisted, isTrue);
    });
  });

  // ===========================================================================
  // TarpitResult
  // ===========================================================================

  group('TarpitResult', () {
    test('construction avec tous les champs', () {
      const result = TarpitResult(
        allowed: true,
        delay: Duration(seconds: 4),
        blacklisted: false,
        failureCount: 3,
      );
      expect(result.allowed, isTrue);
      expect(result.delay, const Duration(seconds: 4));
      expect(result.blacklisted, isFalse);
      expect(result.failureCount, 3);
    });
  });

  // ===========================================================================
  // SecurityTarpit — backoff exponentiel
  // ===========================================================================

  group('SecurityTarpit — backoff exponentiel', () {
    test('identifiant inconnu = autorise, delai zero', () {
      final tarpit = SecurityTarpit();
      final result = tarpit.check('nouveau_user');
      expect(result.allowed, isTrue);
      expect(result.delay, Duration.zero);
      expect(result.blacklisted, isFalse);
      expect(result.failureCount, 0);
    });

    test('1er echec = toujours autorise, delai zero (grace)', () {
      final tarpit = SecurityTarpit();
      final result = tarpit.recordFailure('user');
      expect(result.allowed, isTrue);
      expect(result.delay, Duration.zero);
      expect(result.failureCount, 1);
    });

    test('2e echec = delai 2 secondes', () {
      final tarpit = SecurityTarpit();
      tarpit.recordFailure('user');
      final result = tarpit.recordFailure('user');
      expect(result.delay.inSeconds, 2);
    });

    test('3e echec = delai 4 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('user');
      }
      expect(tarpit.check('user').delay.inSeconds, 4);
    });

    test('4e echec = delai 8 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 4; i++) {
        tarpit.recordFailure('user');
      }
      expect(tarpit.check('user').delay.inSeconds, 8);
    });

    test('5e echec = delai 16 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 5; i++) {
        tarpit.recordFailure('user');
      }
      expect(tarpit.check('user').delay.inSeconds, 16);
    });

    test('6e echec = delai 32 secondes', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 6; i++) {
        tarpit.recordFailure('user');
      }
      expect(tarpit.check('user').delay.inSeconds, 32);
    });

    test('delai ne depasse jamais maxDelay = 60s (par defaut)', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 15; i++) {
        tarpit.recordFailure('user');
      }
      final result = tarpit.check('user');
      expect(result.delay.inSeconds, lessThanOrEqualTo(60));
    });

    test('maxDelay configurable est respecte', () {
      final tarpit = SecurityTarpit(maxDelay: const Duration(seconds: 10));
      for (int i = 0; i < 10; i++) {
        tarpit.recordFailure('user');
      }
      final result = tarpit.check('user');
      expect(result.delay.inSeconds, lessThanOrEqualTo(10));
    });

    test('la sequence de delais est monotone croissante', () {
      final tarpit = SecurityTarpit();
      final delays = <int>[];
      for (int i = 0; i < 8; i++) {
        tarpit.recordFailure('user');
        delays.add(tarpit.check('user').delay.inSeconds);
      }
      for (int i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThanOrEqualTo(delays[i - 1]),
            reason:
                'delays[$i]=${delays[i]} devrait etre >= delays[${i - 1}]=${delays[i - 1]}');
      }
    });

    test('formule exponentielle : failures N -> min(2^(N-1), 60)', () {
      final tarpit = SecurityTarpit();
      // 3 echecs → 2^2 = 4s
      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('u');
      }
      expect(tarpit.check('u').delay.inSeconds, 4);

      final t2 = SecurityTarpit();
      // 7 echecs → 2^6 = 64 → plafonne a 60s
      for (int i = 0; i < 7; i++) {
        t2.recordFailure('u');
      }
      expect(t2.check('u').delay.inSeconds, min(64, 60));
    });
  });

  // ===========================================================================
  // SecurityTarpit — auto-blacklist
  // ===========================================================================

  group('SecurityTarpit — auto-blacklist', () {
    test('blacklist apres 20 echecs (seuil par defaut)', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 20; i++) {
        tarpit.recordFailure('attaquant');
      }
      expect(tarpit.isBlacklisted('attaquant'), isTrue);
    });

    test('19 echecs ne provoquent pas de blacklist', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 19; i++) {
        tarpit.recordFailure('test');
      }
      expect(tarpit.isBlacklisted('test'), isFalse);
    });

    test('blacklist bloque toutes les requetes (allowed = false)', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 20; i++) {
        tarpit.recordFailure('attaquant');
      }
      final result = tarpit.check('attaquant');
      expect(result.allowed, isFalse);
      expect(result.blacklisted, isTrue);
    });

    test('seuil configurable : 5 echecs suffisent', () {
      final tarpit = SecurityTarpit(maxFailuresBeforeBlacklist: 5);
      for (int i = 0; i < 5; i++) {
        tarpit.recordFailure('test');
      }
      expect(tarpit.isBlacklisted('test'), isTrue);
    });

    test('callback onBlacklisted est appele au moment du blacklist', () {
      String? blacklistedId;
      int? capturedFailures;

      final tarpit = SecurityTarpit(
        maxFailuresBeforeBlacklist: 3,
        onBlacklisted: (id, failures) {
          blacklistedId = id;
          capturedFailures = failures;
        },
      );

      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('cible');
      }

      expect(blacklistedId, 'cible');
      expect(capturedFailures, 3);
    });

    test('callback onBlacklisted n est appele qu une seule fois', () {
      int callCount = 0;
      final tarpit = SecurityTarpit(
        maxFailuresBeforeBlacklist: 3,
        onBlacklisted: (id, failures) => callCount++,
      );

      for (int i = 0; i < 6; i++) {
        tarpit.recordFailure('cible');
      }

      expect(callCount, 1);
    });

    test('identifiant inconnu retourne false pour isBlacklisted', () {
      final tarpit = SecurityTarpit();
      expect(tarpit.isBlacklisted('inconnu'), isFalse);
    });
  });

  // ===========================================================================
  // SecurityTarpit — succes et reset
  // ===========================================================================

  group('SecurityTarpit — succes et reset', () {
    test('recordSuccess remet le compteur a zero', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 5; i++) {
        tarpit.recordFailure('user');
      }
      tarpit.recordSuccess('user');

      final result = tarpit.check('user');
      expect(result.failureCount, 0);
      expect(result.delay, Duration.zero);
      expect(result.allowed, isTrue);
    });

    test('recordSuccess sur identifiant inconnu ne provoque pas d erreur', () {
      final tarpit = SecurityTarpit();
      expect(() => tarpit.recordSuccess('fantome'), returnsNormally);
    });
  });

  // ===========================================================================
  // SecurityTarpit — independance des identifiants
  // ===========================================================================

  group('SecurityTarpit — independance des identifiants', () {
    test('deux identifiants differents ont des compteurs independants', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 10; i++) {
        tarpit.recordFailure('user_a');
      }
      tarpit.recordFailure('user_b');

      expect(tarpit.check('user_a').failureCount, 10);
      expect(tarpit.check('user_b').failureCount, 1);
    });

    test('blacklist de user_a ne bloque pas user_b', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 20; i++) {
        tarpit.recordFailure('user_a');
      }
      tarpit.recordFailure('user_b');

      expect(tarpit.isBlacklisted('user_a'), isTrue);
      expect(tarpit.isBlacklisted('user_b'), isFalse);
      expect(tarpit.check('user_b').allowed, isTrue);
    });
  });

  // ===========================================================================
  // SecurityTarpit — statistiques
  // ===========================================================================

  group('SecurityTarpit — statistiques', () {
    test('stats contient les cles attendues', () {
      final tarpit = SecurityTarpit();
      final s = tarpit.stats;
      expect(s.containsKey('total_tracked'), isTrue);
      expect(s.containsKey('blacklisted'), isTrue);
      expect(s.containsKey('total_failures'), isTrue);
    });

    test('stats compte correctement les identifiants suivis', () {
      final tarpit = SecurityTarpit();
      tarpit.recordFailure('a');
      tarpit.recordFailure('b');
      tarpit.recordFailure('c');

      expect(tarpit.stats['total_tracked'], 3);
    });

    test('stats compte le total des echecs', () {
      final tarpit = SecurityTarpit();
      for (int i = 0; i < 5; i++) {
        tarpit.recordFailure('a');
      }
      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('b');
      }

      expect(tarpit.stats['total_failures'], 8);
    });

    test('stats.blacklisted compte les identifiants blacklistes', () {
      final tarpit = SecurityTarpit(maxFailuresBeforeBlacklist: 3);
      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('x');
      }
      tarpit.recordFailure('y');

      expect(tarpit.stats['blacklisted'], 1);
    });
  });

  // ===========================================================================
  // SecurityTarpit — nettoyage
  // ===========================================================================

  group('SecurityTarpit — cleanup et unblacklist', () {
    test('cleanup ne supprime pas les entrees recentes', () {
      final tarpit = SecurityTarpit();
      tarpit.recordFailure('recente');
      tarpit.cleanup();

      // L'entree recente doit toujours etre presente.
      expect(tarpit.stats['total_tracked'], 1);
    });

    test('unblacklist supprime le blacklist d un identifiant', () {
      final tarpit = SecurityTarpit(maxFailuresBeforeBlacklist: 3);
      for (int i = 0; i < 3; i++) {
        tarpit.recordFailure('cible');
      }
      expect(tarpit.isBlacklisted('cible'), isTrue);

      tarpit.unblacklist('cible');
      expect(tarpit.isBlacklisted('cible'), isFalse);
    });
  });
}
