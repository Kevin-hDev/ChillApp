import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chill_app/features/lock/lock_provider.dart';
import 'package:chill_app/core/security/secure_storage.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Reset SecureStorage singleton so each test starts fresh.
    // In tests, SecureStorage will use FallbackSecureStorage (no secret-tool).
    SecureStorage.resetForTesting();
    container = ProviderContainer();
    // Trigger initial build (async _initAsync).
    container.read(lockProvider);
  });

  tearDown(() {
    container.dispose();
    SecureStorage.resetForTesting();
  });

  /// Wait for the async _initAsync() to finish.
  /// Uses a longer delay to allow Process.run('which', ['secret-tool']) to complete.
  Future<void> waitForLoad() async {
    // Allow the async _initAsync future (including Process.run) to complete.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  // ============================================
  // 1. setPin() avec PIN valide
  // ============================================
  group('setPin', () {
    test('PIN valide (8 chiffres) → isEnabled = true, isUnlocked = true',
        () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');

      final state = container.read(lockProvider);
      expect(state.isEnabled, true);
      expect(state.isUnlocked, true);
    });

    // ============================================
    // 2. setPin() avec PIN invalide → ArgumentError
    // ============================================
    test('PIN vide → ArgumentError', () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin(''), throwsArgumentError);
    });

    test('PIN trop court (4 chiffres) → ArgumentError', () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('1234'), throwsArgumentError);
    });

    test('PIN trop long (9 chiffres) → ArgumentError', () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('123456789'), throwsArgumentError);
    });

    test('PIN avec lettres → ArgumentError', () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      expect(() => notifier.setPin('1234abcd'), throwsArgumentError);
    });
  });

  // ============================================
  // 3. verifyPin() avec PIN correct
  // ============================================
  group('verifyPin', () {
    test('PIN correct → true, failedAttempts = 0', () async {
      await waitForLoad();
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
      await waitForLoad();
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
      await waitForLoad();
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
      await waitForLoad();
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
      await waitForLoad();
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
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      notifier.lock();

      for (int i = 0; i < 5; i++) {
        await notifier.verifyPin('00000000');
      }

      final state = container.read(lockProvider);
      final lockDuration =
          state.lockedUntil!.difference(DateTime.now()).inSeconds;
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
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);
      await notifier.setPin('12345678');
      notifier.lock();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pin_failed_attempts', 9);
      await prefs.setInt('pin_locked_until', pastMs);
      // Reload state from prefs
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      final notifier2 = container.read(lockProvider.notifier);
      await notifier2.verifyPin('00000000'); // 10th failure

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 10);
      final lockDuration =
          state.lockedUntil!.difference(DateTime.now()).inSeconds;
      expect(lockDuration, greaterThan(55));
      expect(lockDuration, lessThanOrEqualTo(61));
    });

    test('backoff exponentiel : 15 echecs → ~120s', () async {
      // Pre-seed 14 failed attempts so next failure is the 15th.
      final pastMs = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);
      await notifier.setPin('12345678');
      notifier.lock();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pin_failed_attempts', 14);
      await prefs.setInt('pin_locked_until', pastMs);
      // Reload state from prefs
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      final notifier2 = container.read(lockProvider.notifier);
      await notifier2.verifyPin('00000000'); // 15th failure

      final state = container.read(lockProvider);
      expect(state.failedAttempts, 15);
      final lockDuration =
          state.lockedUntil!.difference(DateTime.now()).inSeconds;
      expect(lockDuration, greaterThan(115));
      expect(lockDuration, lessThanOrEqualTo(121));
    });

    test('PIN correct apres echecs remet failedAttempts a zero', () async {
      await waitForLoad();
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
      await waitForLoad();
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

    test('removePin efface les cles sensibles et le rate limiting', () async {
      await waitForLoad();
      final notifier = container.read(lockProvider.notifier);

      await notifier.setPin('12345678');
      await notifier.removePin();

      // pin_hash and pin_salt are in SecureStorage, not SharedPreferences.
      // After removePin(), SecureStorage should not contain them either.
      final storage = await SecureStorage.getInstance();
      expect(await storage.containsKey('pin_hash'), isFalse);
      expect(await storage.containsKey('pin_salt'), isFalse);

      // Rate limiting data is in SharedPreferences — must be removed.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('pin_failed_attempts'), isNull);
      expect(prefs.getInt('pin_locked_until'), isNull);

      // Legacy SharedPreferences keys must also be absent.
      expect(prefs.getString('pin_hash'), isNull);
      expect(prefs.getString('pin_salt'), isNull);
    });
  });

  // ============================================
  // 8. Migration ancien format → SecureStorage
  // ============================================
  group('Migration legacy SharedPreferences → SecureStorage', () {
    test('migration : pin_hash en SharedPreferences est transfere vers SecureStorage',
        () async {
      // Simulate data left by a pre-FIX-027 version
      const pin = '12345678';
      // Use a PBKDF2 hash directly stored in SharedPreferences (old behaviour)
      // We use a fake 44-char base64 string to simulate a migrated hash.
      // In reality, the old code stored it in SharedPreferences.
      const fakeHash = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 44 chars
      const fakeSalt = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 24 chars base64

      SharedPreferences.setMockInitialValues({
        'pin_hash': fakeHash,
        'pin_salt': fakeSalt,
      });
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      // After migration, pin_hash must be removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pin_hash'), isNull);
      expect(prefs.getString('pin_salt'), isNull);

      // And must be present in SecureStorage
      final storage = await SecureStorage.getInstance();
      expect(await storage.containsKey('pin_hash'), isTrue);
      expect(await storage.containsKey('pin_salt'), isTrue);
      expect(await storage.read('pin_hash'), equals(fakeHash));
      expect(await storage.read('pin_salt'), equals(fakeSalt));
    });

    test('migration SHA-256 sans sel (pre-v1) : verifyPin reussit et migre vers PBKDF2',
        () async {
      // Simulate very old format: sha256(pin) stored in SharedPreferences
      const pin = '12345678';
      final oldHash = sha256.convert(utf8.encode(pin)).toString();

      SharedPreferences.setMockInitialValues({
        'pin_hash': oldHash,
        // No pin_salt = pre-v1 format
      });
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      final notifier = container.read(lockProvider.notifier);
      expect(container.read(lockProvider).isEnabled, true);

      // Verify with the old PIN — triggers migration to PBKDF2
      final result = await notifier.verifyPin(pin);
      expect(result, true);

      // After migration, the hash in SecureStorage must be PBKDF2 (44 chars)
      final storage = await SecureStorage.getInstance();
      final newHash = await storage.read('pin_hash');
      final newSalt = await storage.read('pin_salt');
      expect(newSalt, isNotNull);
      expect(newHash, isNotNull);
      expect(newHash!.length, 44); // base64 encoded PBKDF2
      expect(newHash, isNot(oldHash));
    });

    test('migration SHA-256 avec sel (v1) → PBKDF2 via SecureStorage', () async {
      // Simulate old format: sha256('$salt:$pin') stored in SharedPreferences
      const pin = '12345678';
      final salt = base64Encode(List.generate(16, (i) => i));
      final legacyHash =
          sha256.convert(utf8.encode('$salt:$pin')).toString();

      SharedPreferences.setMockInitialValues({
        'pin_hash': legacyHash,
        'pin_salt': salt,
      });
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      final notifier = container.read(lockProvider.notifier);
      expect(container.read(lockProvider).isEnabled, true);

      // Verify with the old PIN — triggers migration to PBKDF2
      final result = await notifier.verifyPin(pin);
      expect(result, true);

      // After migration, hash must be PBKDF2 in SecureStorage
      final storage = await SecureStorage.getInstance();
      final newHash = await storage.read('pin_hash');
      expect(newHash, isNotNull);
      expect(newHash!.length, 44);
      expect(newHash, isNot(legacyHash));
    });

    test('mauvais PIN sur ancien format → pas de migration', () async {
      const pin = '12345678';
      final oldHash = sha256.convert(utf8.encode(pin)).toString();

      SharedPreferences.setMockInitialValues({
        'pin_hash': oldHash,
      });
      container.dispose();
      SecureStorage.resetForTesting();
      container = ProviderContainer();
      container.read(lockProvider);
      await waitForLoad();

      final notifier = container.read(lockProvider.notifier);
      final result = await notifier.verifyPin('00000000');
      expect(result, false);

      // The hash in SecureStorage must remain the migrated original
      // (migration of the hash itself happened in _initAsync, but
      // the PBKDF2 upgrade only happens on correct PIN).
      final storage = await SecureStorage.getInstance();
      final storedHash = await storage.read('pin_hash');
      // The hash was migrated to SecureStorage by _initAsync,
      // but NOT upgraded to PBKDF2 since the PIN was wrong.
      expect(storedHash, equals(oldHash));
    });
  });
}
