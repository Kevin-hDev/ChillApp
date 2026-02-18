// Tests FIX-054 : Network Segmentation
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/network_segmentation.dart';

void main() {
  // =========================================================
  // SegmentationConfig
  // =========================================================
  group('SegmentationConfig', () {
    test('cree une config avec les valeurs par defaut', () {
      const config = SegmentationConfig(allowedTargetIp: '100.64.1.10');
      expect(config.allowedTargetIp, equals('100.64.1.10'));
      expect(config.allowedPort, equals(22));
      expect(config.strictMode, isTrue);
    });

    test('accepte un port personnalise', () {
      const config = SegmentationConfig(
        allowedTargetIp: '100.64.1.10',
        allowedPort: 2222,
        strictMode: false,
      );
      expect(config.allowedPort, equals(2222));
      expect(config.strictMode, isFalse);
    });
  });

  // =========================================================
  // checkOutgoing
  // =========================================================
  group('NetworkSegmentation.checkOutgoing', () {
    late NetworkSegmentation seg;

    setUp(() {
      seg = NetworkSegmentation(
        config: const SegmentationConfig(
          allowedTargetIp: '100.64.1.10',
          allowedPort: 22,
        ),
      );
    });

    test('autorise la connexion vers l IP et le port corrects', () {
      final check = seg.checkOutgoing(
        destinationIp: '100.64.1.10',
        destinationPort: 22,
      );
      expect(check.allowed, isTrue);
      expect(check.blockedReason, isNull);
    });

    test('bloque une IP non autorisee', () {
      final check = seg.checkOutgoing(
        destinationIp: '100.64.1.99',
        destinationPort: 22,
      );
      expect(check.allowed, isFalse);
      expect(check.blockedReason, contains('100.64.1.99'));
      expect(check.blockedReason, contains('100.64.1.10'));
    });

    test('bloque un port non autorise', () {
      final check = seg.checkOutgoing(
        destinationIp: '100.64.1.10',
        destinationPort: 443,
      );
      expect(check.allowed, isFalse);
      expect(check.blockedReason, contains('443'));
      expect(check.blockedReason, contains('22'));
    });

    test('bloque une IP LAN locale', () {
      final check = seg.checkOutgoing(
        destinationIp: '192.168.1.50',
        destinationPort: 22,
      );
      expect(check.allowed, isFalse);
    });

    test('bloque une IP publique', () {
      final check = seg.checkOutgoing(
        destinationIp: '8.8.8.8',
        destinationPort: 22,
      );
      expect(check.allowed, isFalse);
    });
  });

  // =========================================================
  // checkIncoming
  // =========================================================
  group('NetworkSegmentation.checkIncoming', () {
    late NetworkSegmentation seg;

    setUp(() {
      seg = NetworkSegmentation(
        config: const SegmentationConfig(allowedTargetIp: '100.64.1.10'),
      );
    });

    test('autorise les IPs dans la plage Tailscale 100.64.0.0/10', () {
      final ips = [
        '100.64.0.1',
        '100.64.255.255',
        '100.100.0.1',
        '100.127.255.255',
      ];
      for (final ip in ips) {
        final check = seg.checkIncoming(sourceIp: ip);
        expect(check.allowed, isTrue, reason: '$ip devrait etre autorise');
      }
    });

    test('bloque les IPs hors plage Tailscale', () {
      final ips = [
        '192.168.1.1',
        '10.0.0.1',
        '172.16.0.1',
        '8.8.8.8',
        '100.63.255.255', // Juste avant la plage
        '100.128.0.0', // Juste apres la plage
      ];
      for (final ip in ips) {
        final check = seg.checkIncoming(sourceIp: ip);
        expect(check.allowed, isFalse, reason: '$ip devrait etre bloque');
      }
    });

    test('bloque une IP mal formee (trop peu d octets)', () {
      final check = seg.checkIncoming(sourceIp: '100.64.1');
      expect(check.allowed, isFalse);
      expect(check.blockedReason, isNotNull);
    });

    test('bloque une IP avec des octets invalides', () {
      final check = seg.checkIncoming(sourceIp: '100.64.abc.1');
      expect(check.allowed, isFalse);
    });

    test('bloque une IP vide', () {
      final check = seg.checkIncoming(sourceIp: '');
      expect(check.allowed, isFalse);
    });
  });

  // =========================================================
  // isTargetIpValid
  // =========================================================
  group('NetworkSegmentation.isTargetIpValid', () {
    test('retourne true pour une IP Tailscale valide', () {
      final seg = NetworkSegmentation(
        config: const SegmentationConfig(allowedTargetIp: '100.64.1.10'),
      );
      expect(seg.isTargetIpValid(), isTrue);
    });

    test('retourne false pour une IP LAN locale', () {
      final seg = NetworkSegmentation(
        config: const SegmentationConfig(allowedTargetIp: '192.168.1.10'),
      );
      expect(seg.isTargetIpValid(), isFalse);
    });
  });

  // =========================================================
  // generateAclTemplate
  // =========================================================
  group('NetworkSegmentation.generateAclTemplate', () {
    test('genere un JSON valide', () {
      final json = NetworkSegmentation.generateAclTemplate(
        appTag: 'chillapp-bridge',
        targetTag: 'chillapp-target',
        sshPort: 22,
      );
      // Doit etre parseable
      expect(json, isNotEmpty);
      expect(json, contains('chillapp-bridge'));
      expect(json, contains('chillapp-target'));
      expect(json, contains('22'));
    });

    test('contient les sections acls, tagOwners et ssh', () {
      final json = NetworkSegmentation.generateAclTemplate(
        appTag: 'bridge',
        targetTag: 'target',
        sshPort: 22,
      );
      expect(json, contains('"acls"'));
      expect(json, contains('"tagOwners"'));
      expect(json, contains('"ssh"'));
    });

    test('la regle ssh utilise autogroup:nonroot', () {
      final json = NetworkSegmentation.generateAclTemplate(
        appTag: 'bridge',
        targetTag: 'target',
        sshPort: 22,
      );
      expect(json, contains('autogroup:nonroot'));
    });

    test('supporte un port personnalise', () {
      final json = NetworkSegmentation.generateAclTemplate(
        appTag: 'bridge',
        targetTag: 'target',
        sshPort: 2222,
      );
      expect(json, contains('2222'));
    });
  });

  // =========================================================
  // generateIptablesRules
  // =========================================================
  group('NetworkSegmentation.generateIptablesRules', () {
    test('genere des regles avec l IP et le port specifies', () {
      final rules = NetworkSegmentation.generateIptablesRules(
        tailscaleIp: '100.64.1.5',
        sshPort: 22,
      );
      expect(rules, contains('100.64.1.5'));
      expect(rules, contains('22'));
    });

    test('inclut une regle ACCEPT pour l IP autorisee', () {
      final rules = NetworkSegmentation.generateIptablesRules(
        tailscaleIp: '100.64.1.5',
        sshPort: 22,
      );
      expect(rules, contains('-j ACCEPT'));
    });

    test('inclut une regle DROP pour le reste', () {
      final rules = NetworkSegmentation.generateIptablesRules(
        tailscaleIp: '100.64.1.5',
        sshPort: 22,
      );
      expect(rules, contains('-j DROP'));
    });

    test('bloque l acces aux plages LAN privees', () {
      final rules = NetworkSegmentation.generateIptablesRules(
        tailscaleIp: '100.64.1.5',
        sshPort: 22,
      );
      expect(rules, contains('192.168.0.0/16'));
      expect(rules, contains('10.0.0.0/8'));
      expect(rules, contains('172.16.0.0/12'));
    });

    test('commence par un shebang bash', () {
      final rules = NetworkSegmentation.generateIptablesRules(
        tailscaleIp: '100.64.1.5',
        sshPort: 22,
      );
      expect(rules, startsWith('#!/bin/bash'));
    });
  });

  // =========================================================
  // SegmentationCheck
  // =========================================================
  group('SegmentationCheck', () {
    test('toString indique allowed quand autorise', () {
      const check = SegmentationCheck(allowed: true);
      expect(check.toString(), contains('allowed'));
    });

    test('toString indique la raison du blocage', () {
      const check = SegmentationCheck(
        allowed: false,
        blockedReason: 'IP non autorisee',
      );
      expect(check.toString(), contains('IP non autorisee'));
    });
  });
}
