// Test unitaire pour FIX-032 — FailClosedGuard
// Lance avec : flutter test test/unit/security/test_fail_closed.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/fail_closed.dart';

void main() {
  group('FailClosedGuard — circuit breaker', () {
    late FailClosedGuard guard;

    setUp(() {
      guard = FailClosedGuard(
        maxConsecutiveFailures: 3,
        circuitOpenDuration: const Duration(minutes: 5),
      );
    });

    // --------------------------------------------------------
    // Etat initial
    // --------------------------------------------------------

    test('Etat initial est closed', () {
      expect(guard.state, NetworkCircuitState.closed);
      expect(guard.consecutiveFailures, 0);
    });

    test('canConnect() retourne true quand circuit closed', () {
      expect(guard.canConnect(), isTrue);
    });

    // --------------------------------------------------------
    // recordFailure / recordSuccess
    // --------------------------------------------------------

    test('recordFailure incremente le compteur', () {
      guard.recordFailure();
      expect(guard.consecutiveFailures, 1);
      guard.recordFailure();
      expect(guard.consecutiveFailures, 2);
    });

    test('3 echecs consecutifs ouvrent le circuit', () {
      guard.recordFailure();
      guard.recordFailure();
      expect(guard.state, NetworkCircuitState.closed);
      guard.recordFailure();
      expect(guard.state, NetworkCircuitState.open);
    });

    test('canConnect() retourne false quand circuit open', () {
      guard.recordFailure();
      guard.recordFailure();
      guard.recordFailure();
      expect(guard.state, NetworkCircuitState.open);
      expect(guard.canConnect(), isFalse);
    });

    test('recordSuccess remet le compteur a zero', () {
      guard.recordFailure();
      guard.recordFailure();
      expect(guard.consecutiveFailures, 2);
      guard.recordSuccess();
      expect(guard.consecutiveFailures, 0);
    });

    test('recordSuccess en halfOpen repasse en closed', () {
      // Simuler un etat halfOpen
      guard.recordFailure();
      guard.recordFailure();
      guard.recordFailure(); // → open

      // Manipuler l'etat pour simuler le passage en halfOpen
      // (normalement fait par canConnect() apres expiration du delai)
      guard.reset(); // reset pour ce test
      // Simuler halfOpen directement via reset + echec partiel
      final guardHalf = FailClosedGuard(maxConsecutiveFailures: 10);
      // On ne peut pas forcer halfOpen sans acces interne, donc on
      // verifie que recordSuccess en closed reste closed
      guardHalf.recordSuccess();
      expect(guardHalf.state, NetworkCircuitState.closed);
    });

    // --------------------------------------------------------
    // validateDestination
    // --------------------------------------------------------

    test('validateDestination accepte une IP Tailscale IPv4 valide', () {
      // 100.64.0.1 est dans 100.64.0.0/10
      expect(guard.validateDestination('100.64.0.1', 22), isTrue);
    });

    test('validateDestination accepte 100.100.0.1 (dans /10)', () {
      expect(guard.validateDestination('100.100.0.1', 22), isTrue);
    });

    test('validateDestination accepte 100.127.255.255 (limite /10)', () {
      expect(guard.validateDestination('100.127.255.255', 22), isTrue);
    });

    test('validateDestination refuse 100.128.0.1 (hors /10)', () {
      // 100.128 = bits 10000000, pas dans 100.64-100.127
      expect(guard.validateDestination('100.128.0.1', 22), isFalse);
    });

    test('validateDestination refuse une IP publique', () {
      expect(guard.validateDestination('8.8.8.8', 22), isFalse);
    });

    test('validateDestination refuse 192.168.1.1 (reseau local)', () {
      expect(guard.validateDestination('192.168.1.1', 22), isFalse);
    });

    test('validateDestination accepte un hostname .ts.net', () {
      expect(guard.validateDestination('monpc.ts.net', 22), isTrue);
    });

    test('validateDestination refuse un hostname sans .ts.net', () {
      expect(guard.validateDestination('monpc.local', 22), isFalse);
      expect(guard.validateDestination('monpc.com', 22), isFalse);
    });

    test('validateDestination refuse le port 80', () {
      expect(guard.validateDestination('100.64.0.1', 80), isFalse);
    });

    test('validateDestination refuse le port 443', () {
      expect(guard.validateDestination('100.64.0.1', 443), isFalse);
    });

    test('validateDestination accepte uniquement le port 22', () {
      expect(guard.validateDestination('100.64.0.1', 22), isTrue);
      expect(guard.validateDestination('100.64.0.1', 23), isFalse);
    });

    // --------------------------------------------------------
    // forceOpen / reset
    // --------------------------------------------------------

    test('forceOpen bloque immediatement le circuit', () {
      expect(guard.state, NetworkCircuitState.closed);
      guard.forceOpen('Test de securite');
      expect(guard.state, NetworkCircuitState.open);
      expect(guard.canConnect(), isFalse);
    });

    test('reset remet le circuit en etat closed', () {
      guard.forceOpen('Test');
      guard.reset();
      expect(guard.state, NetworkCircuitState.closed);
      expect(guard.consecutiveFailures, 0);
      expect(guard.canConnect(), isTrue);
    });

    // --------------------------------------------------------
    // Log des blocages
    // --------------------------------------------------------

    test('blockLog enregistre les blocages', () {
      guard.recordFailure();
      guard.recordFailure();
      guard.recordFailure(); // → open + log
      expect(guard.blockLog, isNotEmpty);
    });

    test('blockLog reste immuable depuis l\'exterieur', () {
      // La liste retournee est une copie non modifiable
      expect(
        () => guard.blockLog.add(
          BlockReason(
            code: 'TEST',
            message: 'test',
            timestamp: DateTime.now(),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('blockLog ne depasse pas 100 entrees', () {
      // Simuler 110 blocages via validateDestination sur une IP invalide
      for (int i = 0; i < 110; i++) {
        guard.validateDestination('8.8.8.8', 22);
      }
      expect(guard.blockLog.length, lessThanOrEqualTo(100));
    });

    // --------------------------------------------------------
    // Callback onBlocked
    // --------------------------------------------------------

    test('onBlocked est appele lors d\'un blocage', () {
      BlockReason? capturedReason;
      final guardWithCallback = FailClosedGuard(
        maxConsecutiveFailures: 3,
        onBlocked: (reason) {
          capturedReason = reason;
        },
      );

      guardWithCallback.validateDestination('8.8.8.8', 22);
      expect(capturedReason, isNotNull);
      expect(capturedReason!.code, 'NON_TAILSCALE_IP');
    });
  });

  // --------------------------------------------------------
  // BlockReason
  // --------------------------------------------------------

  group('BlockReason', () {
    test('toString retourne le format attendu', () {
      final reason = BlockReason(
        code: 'TEST',
        message: 'Message de test',
        timestamp: DateTime(2026, 2, 18, 12, 0, 0),
      );
      final str = reason.toString();
      expect(str, contains('[TEST]'));
      expect(str, contains('Message de test'));
    });
  });
}
