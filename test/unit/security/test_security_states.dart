// Test pour FIX-005 : Sealed classes pour états de sécurité
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/security_states.dart';

void main() {
  group('LockSecurityState', () {
    test('LockDisabled est un LockSecurityState valide', () {
      final state = LockDisabled();
      expect(state, isA<LockSecurityState>());
    });

    test('LockUnlocked est un LockSecurityState valide', () {
      final state = LockUnlocked();
      expect(state, isA<LockSecurityState>());
    });

    test('LockActive calcule isTemporarilyLocked correctement (futur)', () {
      final future = LockActive(
        failedAttempts: 5,
        lockedUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(future.isTemporarilyLocked, isTrue);
    });

    test('LockActive calcule isTemporarilyLocked correctement (passé)', () {
      final past = LockActive(
        failedAttempts: 5,
        lockedUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(past.isTemporarilyLocked, isFalse);
    });

    test('LockActive sans lockedUntil : isTemporarilyLocked = false', () {
      final none = LockActive(failedAttempts: 2);
      expect(none.isTemporarilyLocked, isFalse);
    });

    test('LockActive.remainingLockTime retourne la durée restante', () {
      final state = LockActive(
        lockedUntil: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(state.remainingLockTime, isNotNull);
      expect(state.remainingLockTime!.inMinutes, greaterThanOrEqualTo(4));
    });

    test('LockActive.remainingLockTime retourne null quand pas de verrou', () {
      final state = LockActive();
      expect(state.remainingLockTime, isNull);
    });

    test('LockActive.remainingLockTime retourne null quand expiré', () {
      final state = LockActive(
        lockedUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(state.remainingLockTime, isNull);
    });

    test('LockActive.failedAttempts vaut 0 par défaut', () {
      final state = LockActive();
      expect(state.failedAttempts, equals(0));
    });

    test('LockCompromised stocke la raison', () {
      final state = LockCompromised('Brute force détecté');
      expect(state.reason, equals('Brute force détecté'));
    });

    test('switch exhaustif couvre tous les cas LockSecurityState', () {
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
    test('DaemonStopped est un DaemonConnectionState valide', () {
      final state = DaemonStopped();
      expect(state, isA<DaemonConnectionState>());
    });

    test('DaemonStarting stocke le chemin du binaire', () {
      final state = DaemonStarting('/usr/bin/tailscaled');
      expect(state.binaryPath, equals('/usr/bin/tailscaled'));
    });

    test('DaemonConnected stocke le PID', () {
      final state = DaemonConnected(4242);
      expect(state.pid, equals(4242));
    });

    test('DaemonError stocke le message d erreur', () {
      final state = DaemonError('crash inattendu');
      expect(state.error, equals('crash inattendu'));
      expect(state.integrityFailed, isFalse);
    });

    test('DaemonError avec integrityFailed = true', () {
      final state = DaemonError('hash mismatch', integrityFailed: true);
      expect(state.integrityFailed, isTrue);
    });

    test('switch exhaustif couvre tous les cas DaemonConnectionState', () {
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
  });
}
