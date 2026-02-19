// Test pour FIX-005 : Sealed classes pour etats de securite
import 'package:test/test.dart';

import 'fix_005_sealed_security_states.dart';

void main() {
  group('LockSecurityState', () {
    test('LockDisabled est un etat valide', () {
      final state = LockDisabled();
      expect(state, isA<LockSecurityState>());
    });

    test('LockActive calcule isTemporarilyLocked correctement', () {
      // Verrouille jusqu'a dans 1 heure
      final future = LockActive(
        failedAttempts: 5,
        lockedUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(future.isTemporarilyLocked, isTrue);

      // Verrouillage expire
      final past = LockActive(
        failedAttempts: 5,
        lockedUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(past.isTemporarilyLocked, isFalse);

      // Pas de verrouillage temporel
      final none = LockActive(failedAttempts: 2);
      expect(none.isTemporarilyLocked, isFalse);
    });

    test('LockActive.remainingLockTime retourne la duree restante', () {
      final state = LockActive(
        lockedUntil: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(state.remainingLockTime, isNotNull);
      expect(state.remainingLockTime!.inMinutes, greaterThanOrEqualTo(4));
    });

    test('LockCompromised stocke la raison', () {
      final state = LockCompromised('Brute force detecte');
      expect(state.reason, equals('Brute force detecte'));
    });

    test('switch exhaustif couvre tous les cas', () {
      // Ce test verifie que le switch compile sans warning
      String describe(LockSecurityState state) {
        return switch (state) {
          LockDisabled() => 'disabled',
          LockActive() => 'active',
          LockUnlocked() => 'unlocked',
          LockCompromised() => 'compromised',
        };
      }

      expect(describe(LockDisabled()), equals('disabled'));
      expect(describe(LockUnlocked()), equals('unlocked'));
      expect(describe(LockActive()), equals('active'));
      expect(describe(LockCompromised('test')), equals('compromised'));
    });
  });

  group('DaemonConnectionState', () {
    test('switch exhaustif couvre tous les cas', () {
      String describe(DaemonConnectionState state) {
        return switch (state) {
          DaemonStopped() => 'stopped',
          DaemonStarting() => 'starting',
          DaemonConnected() => 'connected',
          DaemonError() => 'error',
        };
      }

      expect(describe(DaemonStopped()), equals('stopped'));
      expect(describe(DaemonStarting('/path/bin')), equals('starting'));
      expect(describe(DaemonConnected(1234)), equals('connected'));
      expect(describe(DaemonError('crash')), equals('error'));
    });

    test('DaemonError avec integrityFailed', () {
      final state = DaemonError('hash mismatch', integrityFailed: true);
      expect(state.integrityFailed, isTrue);
    });
  });
}
