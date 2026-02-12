import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/shared/models/setup_step.dart';
import 'package:chill_app/features/ssh_setup/ssh_setup_provider.dart';
import 'package:chill_app/features/wol_setup/wol_setup_provider.dart';
import 'package:chill_app/features/connection_info/connection_info_provider.dart';
import 'package:chill_app/features/dashboard/dashboard_provider.dart';
import 'package:chill_app/features/tailscale/tailscale_provider.dart';
import 'package:chill_app/features/lock/lock_provider.dart';

void main() {
  // ============================================
  // SetupStep
  // ============================================
  group('SetupStep', () {
    test('valeurs par défaut', () {
      const step = SetupStep(id: 'test');
      expect(step.id, 'test');
      expect(step.status, StepStatus.pending);
      expect(step.errorDetail, isNull);
    });

    test('copyWith change le statut', () {
      const step = SetupStep(id: 'test');
      final updated = step.copyWith(status: StepStatus.success);
      expect(updated.id, 'test');
      expect(updated.status, StepStatus.success);
      expect(updated.errorDetail, isNull);
    });

    test('copyWith ajoute un message d\'erreur', () {
      const step = SetupStep(id: 'test');
      final updated = step.copyWith(
        status: StepStatus.error,
        errorDetail: 'Échec',
      );
      expect(updated.status, StepStatus.error);
      expect(updated.errorDetail, 'Échec');
    });

    test('copyWith ne modifie pas l\'original', () {
      const step = SetupStep(id: 'original');
      step.copyWith(status: StepStatus.running);
      expect(step.status, StepStatus.pending);
    });
  });

  // ============================================
  // SshSetupState
  // ============================================
  group('SshSetupState', () {
    test('valeurs par défaut', () {
      const state = SshSetupState();
      expect(state.steps, isEmpty);
      expect(state.isRunning, false);
      expect(state.isComplete, false);
      expect(state.ipEthernet, isNull);
      expect(state.ipWifi, isNull);
      expect(state.username, isNull);
      expect(state.errorMessage, isNull);
    });

    test('copyWith met à jour isRunning', () {
      const state = SshSetupState();
      final updated = state.copyWith(isRunning: true);
      expect(updated.isRunning, true);
      expect(updated.isComplete, false);
    });

    test('copyWith met à jour les infos de connexion', () {
      const state = SshSetupState();
      final updated = state.copyWith(
        ipEthernet: '192.168.1.10',
        ipWifi: '192.168.1.20',
        username: 'kevin',
        isComplete: true,
      );
      expect(updated.ipEthernet, '192.168.1.10');
      expect(updated.ipWifi, '192.168.1.20');
      expect(updated.username, 'kevin');
      expect(updated.isComplete, true);
    });

    test('copyWith efface errorMessage quand null passé', () {
      final state = const SshSetupState().copyWith(errorMessage: 'erreur');
      expect(state.errorMessage, 'erreur');
      // errorMessage n'est PAS optionnel dans copyWith, il est nullable
      final cleared = state.copyWith(errorMessage: null);
      expect(cleared.errorMessage, isNull);
    });

    test('copyWith avec liste d\'étapes', () {
      const steps = [
        SetupStep(id: 'a'),
        SetupStep(id: 'b', status: StepStatus.success),
      ];
      final state = const SshSetupState().copyWith(steps: steps);
      expect(state.steps.length, 2);
      expect(state.steps[0].id, 'a');
      expect(state.steps[1].status, StepStatus.success);
    });
  });

  // ============================================
  // WolSetupState
  // ============================================
  group('WolSetupState', () {
    test('valeurs par défaut', () {
      const state = WolSetupState();
      expect(state.steps, isEmpty);
      expect(state.isRunning, false);
      expect(state.isComplete, false);
      expect(state.macAddress, isNull);
      expect(state.ipEthernet, isNull);
      expect(state.ipWifi, isNull);
      expect(state.adapterName, isNull);
      expect(state.errorMessage, isNull);
    });

    test('copyWith met à jour l\'adresse MAC', () {
      const state = WolSetupState();
      final updated = state.copyWith(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        adapterName: 'eth0',
        isComplete: true,
      );
      expect(updated.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(updated.adapterName, 'eth0');
      expect(updated.isComplete, true);
    });
  });

  // ============================================
  // ConnectionInfoState
  // ============================================
  group('ConnectionInfoState', () {
    test('valeurs par défaut', () {
      const state = ConnectionInfoState();
      expect(state.ipEthernet, isNull);
      expect(state.ipWifi, isNull);
      expect(state.macAddress, isNull);
      expect(state.username, isNull);
      expect(state.adapterName, isNull);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('copyWith met à jour toutes les infos', () {
      const state = ConnectionInfoState();
      final updated = state.copyWith(
        ipEthernet: '10.0.0.5',
        ipWifi: '10.0.0.15',
        macAddress: '11:22:33:44:55:66',
        username: 'user',
        adapterName: 'enp3s0',
        isLoading: false,
      );
      expect(updated.ipEthernet, '10.0.0.5');
      expect(updated.ipWifi, '10.0.0.15');
      expect(updated.macAddress, '11:22:33:44:55:66');
      expect(updated.username, 'user');
      expect(updated.adapterName, 'enp3s0');
    });
  });

  // ============================================
  // DashboardState
  // ============================================
  group('DashboardState', () {
    test('valeurs par défaut (null = pas encore vérifié)', () {
      const state = DashboardState();
      expect(state.sshConfigured, isNull);
      expect(state.wolConfigured, isNull);
    });

    test('copyWith met à jour les statuts', () {
      const state = DashboardState();
      final updated = state.copyWith(
        sshConfigured: true,
        wolConfigured: false,
      );
      expect(updated.sshConfigured, true);
      expect(updated.wolConfigured, false);
    });
  });

  // ============================================
  // StepStatus enum
  // ============================================
  group('StepStatus', () {
    test('contient les 4 valeurs attendues', () {
      expect(StepStatus.values.length, 4);
      expect(StepStatus.values, contains(StepStatus.pending));
      expect(StepStatus.values, contains(StepStatus.running));
      expect(StepStatus.values, contains(StepStatus.success));
      expect(StepStatus.values, contains(StepStatus.error));
    });
  });

  // ============================================
  // TailscaleState
  // ============================================
  group('TailscaleState', () {
    test('valeurs par défaut', () {
      const state = TailscaleState();
      expect(state.status, TailscaleConnectionStatus.loading);
      expect(state.selfHostname, isNull);
      expect(state.selfIp, isNull);
      expect(state.peers, isEmpty);
      expect(state.errorMessage, isNull);
      expect(state.isLoggingIn, false);
    });

    test('copyWith met à jour le statut et les infos', () {
      const state = TailscaleState();
      final updated = state.copyWith(
        status: TailscaleConnectionStatus.connected,
        selfHostname: 'my-pc',
        selfIp: '100.64.0.1',
      );
      expect(updated.status, TailscaleConnectionStatus.connected);
      expect(updated.selfHostname, 'my-pc');
      expect(updated.selfIp, '100.64.0.1');
    });

    test('copyWith met à jour la liste de peers', () {
      const state = TailscaleState();
      final peers = [
        TailscalePeer(hostname: 'phone', ipv4: '100.64.0.2', os: 'android', isOnline: true),
        TailscalePeer(hostname: 'laptop', ipv4: '100.64.0.3', os: 'windows', isOnline: false),
      ];
      final updated = state.copyWith(peers: peers);
      expect(updated.peers.length, 2);
      expect(updated.peers[0].hostname, 'phone');
      expect(updated.peers[1].isOnline, false);
    });

    test('copyWith efface errorMessage quand null passé', () {
      final state = const TailscaleState().copyWith(errorMessage: 'erreur');
      expect(state.errorMessage, 'erreur');
      final cleared = state.copyWith(errorMessage: null);
      expect(cleared.errorMessage, isNull);
    });
  });

  // ============================================
  // TailscalePeer
  // ============================================
  group('TailscalePeer', () {
    test('crée un peer avec toutes les infos', () {
      const peer = TailscalePeer(
        hostname: 'my-phone',
        ipv4: '100.64.0.5',
        os: 'iOS',
        isOnline: true,
      );
      expect(peer.hostname, 'my-phone');
      expect(peer.ipv4, '100.64.0.5');
      expect(peer.os, 'iOS');
      expect(peer.isOnline, true);
    });
  });

  // ============================================
  // TailscaleConnectionStatus
  // ============================================
  group('TailscaleConnectionStatus', () {
    test('contient les 4 valeurs attendues', () {
      expect(TailscaleConnectionStatus.values.length, 4);
      expect(TailscaleConnectionStatus.values, contains(TailscaleConnectionStatus.loading));
      expect(TailscaleConnectionStatus.values, contains(TailscaleConnectionStatus.loggedOut));
      expect(TailscaleConnectionStatus.values, contains(TailscaleConnectionStatus.connected));
      expect(TailscaleConnectionStatus.values, contains(TailscaleConnectionStatus.error));
    });
  });

  // ============================================
  // LockState
  // ============================================
  group('LockState', () {
    test('valeurs par défaut', () {
      const state = LockState();
      expect(state.isEnabled, false);
      expect(state.isUnlocked, false);
      expect(state.failedAttempts, 0);
    });

    test('copyWith met à jour isEnabled', () {
      const state = LockState();
      final updated = state.copyWith(isEnabled: true);
      expect(updated.isEnabled, true);
      expect(updated.isUnlocked, false);
      expect(updated.failedAttempts, 0);
    });

    test('copyWith met à jour isUnlocked', () {
      const state = LockState();
      final updated = state.copyWith(isUnlocked: true);
      expect(updated.isUnlocked, true);
    });

    test('copyWith met à jour failedAttempts', () {
      const state = LockState();
      final updated = state.copyWith(failedAttempts: 3);
      expect(updated.failedAttempts, 3);
    });

    test('copyWith ne modifie pas l\'original', () {
      const state = LockState();
      state.copyWith(isEnabled: true, isUnlocked: true, failedAttempts: 5);
      expect(state.isEnabled, false);
      expect(state.isUnlocked, false);
      expect(state.failedAttempts, 0);
    });
  });
}
