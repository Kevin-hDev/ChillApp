import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chill_app/features/lock/lock_provider.dart';
import 'package:chill_app/features/settings/settings_provider.dart';

void main() {
  late ProviderContainer container;

  Future<ProviderContainer> createContainer([
    Map<String, Object> initialValues = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
  }

  setUp(() async {
    container = await createContainer();
  });

  tearDown(() {
    container.dispose();
  });

  // ============================================
  // 1. setPin() avec PIN valide
  // ============================================
  group('setPin', () {
    test(
      'PIN valide (8 chiffres) → isEnabled = true, isUnlocked = true',
      () async {
        final notifier = container.read(lockProvider.notifier);

        await notifier.setPin('12345678');

        final state = container.read(lockProvider);
        expect(state.isEnabled, true);
        expect(state.isUnlocked, true);
      },
    );

    // ============================================
    // 2. setPin() avec PIN invalide → ArgumentError
    // ============================================
    test('PIN vide → ArgumentError', () async {
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin(''), throwsArgumentError);
    });

    test('PIN trop court (4 chiffres) → ArgumentError', () async {
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('1234'), throwsArgumentError);
    });

    test('PIN trop long (9 chiffres) → ArgumentError', () async {
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('123456789'), throwsArgumentError);
    });

    test('PIN avec lettres → ArgumentError', () async {
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('1234abcd'), throwsArgumentError);
    });
  });

  // ============================================
  // 3. verifyPin() avec PIN correct
  // ============================================
  group('verifyPin', () {
    test('PIN correct → true, failedAttempts = 0', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      final result = await notifier.verifyPin('12345678');
      final state = container.read(lockProvider);

      expect(result, true);
      expect(state.isUnlocked, true);
      expect(state.failedAttempts, 0);
    });

    // ============================================
    // 4. verifyPin() avec PIN incorrect
    // ============================================
    test('PIN incorrect → false, failedAttempts++', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      final result = await notifier.verifyPin('00000000');
      final state = container.read(lockProvider);

      expect(result, false);
      expect(state.failedAttempts, 1);
      expect(state.isUnlocked, false);
    });

    test('Plusieurs echecs incrementent failedAttempts', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      await notifier.verifyPin('00000000');
      await notifier.verifyPin('11111111');
      await notifier.verifyPin('22222222');

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 3);
    });
  });

  // ============================================
  // 5. Rate limiting : 5 echecs → lock actif
  // ============================================
  group('Rate limiting', () {
    test('5 echecs → lockedUntil non null', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      for (int i = 0; i < 5; i++) {
        await notifier.verifyPin('00000000');
      }

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 5);
      expect(state.lockedUntil, isNotNull);
    });

    test('4 echecs → pas de lock', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      for (int i = 0; i < 4; i++) {
        await notifier.verifyPin('00000000');
      }

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 4);
      expect(state.lockedUntil, isNull);
    });

    // ============================================
    // 6. Backoff exponentiel : 5→30s, 10→60s, 15→120s
    // ============================================
    test('backoff exponentiel : 5 echecs → ~30s', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      for (int i = 0; i < 5; i++) {
        await notifier.verifyPin('00000000');
      }

      final state = container.read(lockProvider);
      final lockDuration = state.lockedUntil!
          .difference(DateTime.now())
          .inSeconds;
      // Should be approximately 30s (allow some tolerance for test execution)
      expect(lockDuration, greaterThan(25));
      expect(lockDuration, lessThanOrEqualTo(31));
    });

    test('backoff exponentiel : 10 echecs → ~60s', () async {
      // Pre-seed 9 failed attempts so next failure is the 10th.
      // Set lockedUntil in the past so rate limiting doesn't block.
      final pastMs = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;

      // Set initial PIN first, then seed failures
      final notifier = container.read(lockProvider.notifier);
      await notifier.setPin('12345678');
      notifier.lock();

      // Seed 9 failures via SharedPreferences and recreate container
      final prefs = await SharedPreferences.getInstance();
      // Keep the pin hash and salt that were just set
      final pinHash = prefs.getString('pin_hash')!;
      final pinSalt = prefs.getString('pin_salt')!;

      container.dispose();
      container = await createContainer({
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
        'pin_failed_attempts': 9,
        'pin_locked_until': pastMs,
      });

      final notifier2 = container.read(lockProvider.notifier);
      await notifier2.verifyPin('00000000'); // 10th failure

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 10);
      final lockDuration = state.lockedUntil!
          .difference(DateTime.now())
          .inSeconds;
      expect(lockDuration, greaterThan(55));
      expect(lockDuration, lessThanOrEqualTo(61));
    });

    test('backoff exponentiel : 15 echecs → ~120s', () async {
      // Pre-seed 14 failed attempts so next failure is the 15th.
      final pastMs = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;

      // Set initial PIN first, then seed failures
      final notifier = container.read(lockProvider.notifier);
      await notifier.setPin('12345678');
      notifier.lock();

      final prefs = await SharedPreferences.getInstance();
      final pinHash = prefs.getString('pin_hash')!;
      final pinSalt = prefs.getString('pin_salt')!;

      container.dispose();
      container = await createContainer({
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
        'pin_failed_attempts': 14,
        'pin_locked_until': pastMs,
      });

      final notifier2 = container.read(lockProvider.notifier);
      await notifier2.verifyPin('00000000'); // 15th failure

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 15);
      final lockDuration = state.lockedUntil!
          .difference(DateTime.now())
          .inSeconds;
      expect(lockDuration, greaterThan(115));
      expect(lockDuration, lessThanOrEqualTo(121));
    });

    test('PIN correct apres echecs remet failedAttempts a zero', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      // 3 echecs
      for (int i = 0; i < 3; i++) {
        await notifier.verifyPin('00000000');
      }
      expect(container.read(lockProvider).failedAttempts, 3);

      // Succes
      final result = await notifier.verifyPin('12345678');
      expect(result, true);
      expect(container.read(lockProvider).failedAttempts, 0);
      expect(container.read(lockProvider).lockedUntil, isNull);
    });
  });

  // ============================================
  // 7. removePin() → isEnabled = false
  // ============================================
  group('removePin', () {
    test('removePin desactive le lock', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      expect(container.read(lockProvider).isEnabled, true);

      await notifier.removePin();
      final state = container.read(lockProvider);
      expect(state.isEnabled, false);
      expect(state.isUnlocked, true);
      expect(state.failedAttempts, 0);
      expect(state.lockedUntil, isNull);
    });

    test('removePin efface le hash de SharedPreferences', () async {
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      await notifier.removePin();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pin_hash'), isNull);
      expect(prefs.getString('pin_salt'), isNull);
      expect(prefs.getInt('pin_failed_attempts'), isNull);
      expect(prefs.getInt('pin_locked_until'), isNull);
    });
  });

  // ============================================
  // 8. Migration ancien format → nouveau format PBKDF2
  // ============================================
  group('Migration legacy hash', () {
    test('migration SHA-256 sans sel (pre-v1) → PBKDF2', () async {
      // Simuler l'ancien format : sha256(pin) sans sel
      const pin = '12345678';
      final oldHash = sha256.convert(utf8.encode(pin)).toString();

      container.dispose();
      container = await createContainer({
        'pin_hash': oldHash,
        // Pas de pin_salt = format pre-v1
      });

      final notifier = container.read(lockProvider.notifier);
      expect(container.read(lockProvider).isEnabled, true);

      // Verifier avec l'ancien PIN → migration
      final result = await notifier.verifyPin(pin);
      expect(result, true);

      // Apres migration, le hash doit avoir change (PBKDF2 = 44 chars base64)
      final prefs = await SharedPreferences.getInstance();
      final newHash = prefs.getString('pin_hash');
      final newSalt = prefs.getString('pin_salt');
      expect(newSalt, isNotNull);
      expect(newHash, isNotNull);
      expect(newHash!.length, 44); // base64 encoded PBKDF2
      expect(newHash, isNot(oldHash));
    });

    test('migration SHA-256 avec sel (v1) → PBKDF2', () async {
      // Simuler l'ancien format : sha256('$salt:$pin') avec sel
      const pin = '12345678';
      final salt = base64Encode(List.generate(16, (i) => i));
      final legacyHash = sha256.convert(utf8.encode('$salt:$pin')).toString();

      container.dispose();
      container = await createContainer({
        'pin_hash': legacyHash,
        'pin_salt': salt,
      });

      final notifier = container.read(lockProvider.notifier);
      expect(container.read(lockProvider).isEnabled, true);

      // Verifier avec l'ancien PIN → migration
      final result = await notifier.verifyPin(pin);
      expect(result, true);

      // Apres migration, le hash doit etre PBKDF2 (44 chars base64)
      final prefs = await SharedPreferences.getInstance();
      final newHash = prefs.getString('pin_hash');
      expect(newHash, isNotNull);
      expect(newHash!.length, 44);
      expect(newHash, isNot(legacyHash));
    });

    test('mauvais PIN sur ancien format → pas de migration', () async {
      const pin = '12345678';
      final oldHash = sha256.convert(utf8.encode(pin)).toString();

      container.dispose();
      container = await createContainer({'pin_hash': oldHash});

      final notifier = container.read(lockProvider.notifier);
      final result = await notifier.verifyPin('00000000');
      expect(result, false);

      // Le hash ne doit pas avoir change
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pin_hash'), oldHash);
      expect(prefs.getString('pin_salt'), isNull);
    });
  });
}
