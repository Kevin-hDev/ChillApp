// Tests unitaires pour FIX-045/055 — Kill Switch + Watchdog
// Lance avec : flutter test test/unit/security/test_kill_switch.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/kill_switch.dart';

// ---------------------------------------------------------------------------
// Sous-classe testable : surcharge les méthodes OS pour éviter les I/O réels
// ---------------------------------------------------------------------------
class TestableKillSwitch extends KillSwitch {
  final List<String> executedSteps = [];

  TestableKillSwitch({super.onTrigger, super.sshDir, super.secureStoragePath});

  @override
  Future<void> wipeSSHKeys() async => executedSteps.add('wipeSSHKeys');

  @override
  Future<void> closeAllSessions() async =>
      executedSteps.add('closeAllSessions');

  @override
  Future<void> disconnectTailscale() async =>
      executedSteps.add('disconnectTailscale');

  @override
  Future<void> clearSensitiveData() async =>
      executedSteps.add('clearSensitiveData');
}

// ---------------------------------------------------------------------------
// Sous-classe qui fait échouer certaines étapes
// ---------------------------------------------------------------------------
class FailingKillSwitch extends KillSwitch {
  @override
  Future<void> wipeSSHKeys() async =>
      throw Exception('Erreur simulee wipeSSHKeys');

  @override
  Future<void> closeAllSessions() async =>
      throw Exception('Erreur simulee closeAllSessions');

  @override
  Future<void> disconnectTailscale() async {}

  @override
  Future<void> clearSensitiveData() async {}
}

void main() {
  // =========================================================================
  // KillReason enum
  // =========================================================================

  group('KillReason enum', () {
    test('a exactement 6 valeurs', () {
      expect(KillReason.values.length, equals(6));
    });

    test('contient toutes les valeurs attendues', () {
      expect(KillReason.values, containsAll([
        KillReason.userTriggered,
        KillReason.heartbeatTimeout,
        KillReason.canaryTriggered,
        KillReason.bruteForceDetected,
        KillReason.aiAgentDetected,
        KillReason.logTamperingDetected,
      ]));
    });
  });

  // =========================================================================
  // KillSwitchResult
  // =========================================================================

  group('KillSwitchResult', () {
    test('sans erreurs → success est true', () {
      const result = KillSwitchResult(
        success: true,
        actionsPerformed: ['action1', 'action2'],
        errors: [],
      );
      expect(result.success, isTrue);
      expect(result.actionsPerformed.length, equals(2));
      expect(result.errors, isEmpty);
    });

    test('avec erreurs → success est false', () {
      const result = KillSwitchResult(
        success: false,
        actionsPerformed: [],
        errors: ['Erreur 1'],
      );
      expect(result.success, isFalse);
      expect(result.errors.length, equals(1));
    });
  });

  // =========================================================================
  // KillSwitch.execute — flux de confirmation PIN
  // =========================================================================

  group('KillSwitch.execute — confirmation PIN', () {
    test('pinConfirmation retourne false → annulation', () async {
      final ks = TestableKillSwitch();
      final result = await ks.execute(
        reason: KillReason.userTriggered,
        pinConfirmation: () async => false,
      );

      expect(result.success, isFalse);
      expect(result.errors, contains('Confirmation PIN refusee'));
      expect(ks.executedSteps, isEmpty);
    });

    test('skipConfirmation=true → passe sans PIN', () async {
      final ks = TestableKillSwitch();
      final result = await ks.execute(
        reason: KillReason.userTriggered,
        pinConfirmation: () async => false, // serait refusé si appelé
        skipConfirmation: true,
      );

      // Les 4 étapes doivent avoir été exécutées
      expect(ks.executedSteps, containsAll([
        'wipeSSHKeys',
        'closeAllSessions',
        'disconnectTailscale',
        'clearSensitiveData',
      ]));
      expect(result.success, isTrue);
    });

    test('pinConfirmation retourne true → exécution complète', () async {
      final ks = TestableKillSwitch();
      final result = await ks.execute(
        reason: KillReason.userTriggered,
        pinConfirmation: () async => true,
      );

      expect(result.success, isTrue);
      expect(ks.executedSteps.length, equals(4));
    });
  });

  // =========================================================================
  // KillSwitch.execute — callback onTrigger
  // =========================================================================

  group('KillSwitch.execute — callback onTrigger', () {
    test('onTrigger est appelé avec la bonne raison', () async {
      KillReason? capturedReason;
      String? capturedDetail;

      final ks = TestableKillSwitch(
        onTrigger: (reason, detail) {
          capturedReason = reason;
          capturedDetail = detail;
        },
      );

      await ks.execute(
        reason: KillReason.aiAgentDetected,
        pinConfirmation: () async => true,
      );

      expect(capturedReason, equals(KillReason.aiAgentDetected));
      expect(capturedDetail, isNotNull);
      expect(capturedDetail, contains('aiAgentDetected'));
    });

    test('onTrigger n\'est pas appelé si PIN refusé', () async {
      bool triggered = false;

      final ks = TestableKillSwitch(
        onTrigger: (_, __) => triggered = true,
      );

      await ks.execute(
        reason: KillReason.userTriggered,
        pinConfirmation: () async => false,
      );

      expect(triggered, isFalse);
    });
  });

  // =========================================================================
  // KillSwitch.execute — résilience face aux erreurs partielles
  // =========================================================================

  group('KillSwitch.execute — résilience erreurs', () {
    test('erreurs partielles collectées sans arrêter les autres étapes',
        () async {
      final ks = FailingKillSwitch();
      final result = await ks.execute(
        reason: KillReason.canaryTriggered,
        pinConfirmation: () async => true,
      );

      // 2 étapes échouent, 2 réussissent → success est false
      expect(result.success, isFalse);
      expect(result.errors.length, equals(2));
      // Les étapes qui réussissent sont quand même dans actionsPerformed
      expect(result.actionsPerformed, isNotEmpty);
    });
  });

  // =========================================================================
  // KillSwitchWatchdog — cycle de vie
  // =========================================================================

  group('KillSwitchWatchdog — cycle de vie', () {
    test('start → isRunning est true', () {
      final ks = TestableKillSwitch();
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 5),
      );
      watchdog.start();

      expect(watchdog.isRunning, isTrue);

      watchdog.stop();
    });

    test('stop → isRunning est false', () {
      final ks = TestableKillSwitch();
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 5),
      );
      watchdog.start();
      watchdog.stop();

      expect(watchdog.isRunning, isFalse);
    });

    test('heartbeat met à jour lastHeartbeat', () async {
      final ks = TestableKillSwitch();
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 5),
      );
      watchdog.start();

      final before = watchdog.lastHeartbeat;
      await Future.delayed(const Duration(milliseconds: 10));
      watchdog.heartbeat();
      final after = watchdog.lastHeartbeat;

      expect(after.isAfter(before), isTrue);

      watchdog.stop();
    });

    test('hasTriggered est false après start', () {
      final ks = TestableKillSwitch();
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 5),
      );
      watchdog.start();

      expect(watchdog.hasTriggered, isFalse);

      watchdog.stop();
    });
  });

  // =========================================================================
  // KillSwitchWatchdog — déclenchement
  // =========================================================================

  group('KillSwitchWatchdog — déclenchement', () {
    test('check déclenche si le heartbeat est expiré', () {
      final ks = TestableKillSwitch();
      // initialLastHeartbeat dans le passé lointain → délai déjà dépassé
      final pastHeartbeat = DateTime.now().subtract(const Duration(minutes: 10));
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 2),
        initialLastHeartbeat: pastHeartbeat,
      );
      watchdog.start();

      // Requiert 3 vérifications consécutives en dépassement (C4 — anti faux-positif)
      watchdog.check();
      expect(watchdog.hasTriggered, isFalse); // Pas encore : 1/3
      watchdog.check();
      expect(watchdog.hasTriggered, isFalse); // Pas encore : 2/3
      watchdog.check();

      expect(watchdog.hasTriggered, isTrue); // 3/3 → déclenchement
      // Le watchdog se stoppe lui-même après déclenchement
      expect(watchdog.isRunning, isFalse);
    });

    test('check ne déclenche pas si heartbeat est récent', () {
      final ks = TestableKillSwitch();
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 10),
      );
      watchdog.start();

      // Heartbeat tout juste enregistré → délai non dépassé
      watchdog.heartbeat();
      watchdog.check();

      expect(watchdog.hasTriggered, isFalse);

      watchdog.stop();
    });

    test('check ne déclenche qu\'une seule fois', () async {
      final ks = TestableKillSwitch();
      // Heartbeat dans le passé lointain pour garantir le déclenchement
      final pastHeartbeat =
          DateTime.now().subtract(const Duration(minutes: 10));
      final watchdog = KillSwitchWatchdog(
        killSwitch: ks,
        heartbeatInterval: const Duration(seconds: 60),
        maxMissedHeartbeats: const Duration(minutes: 2),
        initialLastHeartbeat: pastHeartbeat,
      );
      watchdog.start();

      // Premier check : déclenche
      watchdog.check();
      final stepsAfterFirst = List<String>.from(ks.executedSteps);

      // Deuxième check (manuel, malgré le stop) : ne redéclenche pas
      watchdog.check();

      expect(ks.executedSteps.length, equals(stepsAfterFirst.length),
          reason: 'Le kill switch ne doit être exécuté qu\'une seule fois');
    });
  });
}
