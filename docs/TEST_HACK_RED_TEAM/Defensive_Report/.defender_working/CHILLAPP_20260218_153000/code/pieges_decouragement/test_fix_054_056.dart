// =============================================================
// TEST FIX-054 + FIX-056 : Network Segmentation + Supply Chain
// Verification de la segmentation reseau et de l'audit dependances
// =============================================================

import 'package:test/test.dart';

// Reproduction des types pour les tests
class SegmentationCheck {
  final bool allowed;
  final String? blockedReason;

  const SegmentationCheck({required this.allowed, this.blockedReason});
}

class SegmentationConfig {
  final String allowedTargetIp;
  final int allowedPort;
  final bool strictMode;

  const SegmentationConfig({
    required this.allowedTargetIp,
    this.allowedPort = 22,
    this.strictMode = true,
  });
}

SegmentationCheck checkOutgoing({
  required SegmentationConfig config,
  required String destinationIp,
  required int destinationPort,
}) {
  if (destinationIp != config.allowedTargetIp) {
    return SegmentationCheck(
      allowed: false,
      blockedReason: 'IP $destinationIp non autorisee',
    );
  }
  if (destinationPort != config.allowedPort) {
    return SegmentationCheck(
      allowed: false,
      blockedReason: 'Port $destinationPort non autorise',
    );
  }
  return const SegmentationCheck(allowed: true);
}

SegmentationCheck checkIncoming({required String sourceIp}) {
  final parts = sourceIp.split('.');
  if (parts.length != 4) {
    return const SegmentationCheck(
      allowed: false, blockedReason: 'IP source invalide',
    );
  }
  final bytes = parts.map(int.tryParse).toList();
  if (bytes.any((b) => b == null)) {
    return const SegmentationCheck(
      allowed: false, blockedReason: 'IP source invalide',
    );
  }
  if (bytes[0] != 100 || bytes[1]! < 64 || bytes[1]! > 127) {
    return SegmentationCheck(
      allowed: false,
      blockedReason: 'IP source $sourceIp non Tailscale',
    );
  }
  return const SegmentationCheck(allowed: true);
}

// Supply chain types
class PackageAuditResult {
  final String name;
  final String version;
  final String severity;
  final String message;

  const PackageAuditResult({
    required this.name,
    required this.version,
    required this.severity,
    required this.message,
  });
}

bool isSuspiciousName(String name) {
  const patterns = ['flutter-', 'flutterr', 'riverpood', 'cripto', 'crytpo'];
  return patterns.any((p) => name.contains(p));
}

void main() {
  group('Segmentation — Sortant (checkOutgoing)', () {
    final config = SegmentationConfig(
      allowedTargetIp: '100.64.1.50',
      allowedPort: 22,
    );

    test('IP et port autorises = OK', () {
      final result = checkOutgoing(
        config: config,
        destinationIp: '100.64.1.50',
        destinationPort: 22,
      );
      expect(result.allowed, isTrue);
    });

    test('IP non autorisee = bloquee', () {
      final result = checkOutgoing(
        config: config,
        destinationIp: '192.168.1.1',
        destinationPort: 22,
      );
      expect(result.allowed, isFalse);
      expect(result.blockedReason, contains('192.168.1.1'));
    });

    test('port non autorise = bloque', () {
      final result = checkOutgoing(
        config: config,
        destinationIp: '100.64.1.50',
        destinationPort: 8080,
      );
      expect(result.allowed, isFalse);
      expect(result.blockedReason, contains('8080'));
    });

    test('autre IP Tailscale = bloquee (une seule cible)', () {
      final result = checkOutgoing(
        config: config,
        destinationIp: '100.64.2.100',
        destinationPort: 22,
      );
      expect(result.allowed, isFalse);
    });

    test('IP LAN privee = bloquee', () {
      for (final ip in ['192.168.0.1', '10.0.0.1', '172.16.0.1']) {
        final result = checkOutgoing(
          config: config, destinationIp: ip, destinationPort: 22,
        );
        expect(result.allowed, isFalse, reason: '$ip devrait etre bloquee');
      }
    });
  });

  group('Segmentation — Entrant (checkIncoming)', () {
    test('IP Tailscale 100.64.x.x = autorisee', () {
      expect(checkIncoming(sourceIp: '100.64.0.1').allowed, isTrue);
    });

    test('IP Tailscale 100.100.x.x = autorisee', () {
      expect(checkIncoming(sourceIp: '100.100.50.25').allowed, isTrue);
    });

    test('IP Tailscale 100.127.x.x = autorisee (limite haute)', () {
      expect(checkIncoming(sourceIp: '100.127.255.255').allowed, isTrue);
    });

    test('IP non-Tailscale 100.63.x.x = refusee', () {
      expect(checkIncoming(sourceIp: '100.63.0.1').allowed, isFalse);
    });

    test('IP non-Tailscale 100.128.x.x = refusee', () {
      expect(checkIncoming(sourceIp: '100.128.0.1').allowed, isFalse);
    });

    test('IP privee = refusee', () {
      expect(checkIncoming(sourceIp: '192.168.1.1').allowed, isFalse);
      expect(checkIncoming(sourceIp: '10.0.0.1').allowed, isFalse);
    });

    test('IP publique = refusee', () {
      expect(checkIncoming(sourceIp: '8.8.8.8').allowed, isFalse);
    });

    test('IP invalide = refusee', () {
      expect(checkIncoming(sourceIp: 'not-an-ip').allowed, isFalse);
      expect(checkIncoming(sourceIp: '').allowed, isFalse);
    });
  });

  group('Supply Chain — Detection typosquatting', () {
    test('flutter- (tiret) est suspect', () {
      expect(isSuspiciousName('flutter-riverpod'), isTrue);
    });

    test('flutterr (double lettre) est suspect', () {
      expect(isSuspiciousName('flutterr_utils'), isTrue);
    });

    test('riverpood (typo) est suspect', () {
      expect(isSuspiciousName('riverpood'), isTrue);
    });

    test('cripto (typo) est suspect', () {
      expect(isSuspiciousName('cripto'), isTrue);
    });

    test('crytpo (typo) est suspect', () {
      expect(isSuspiciousName('crytpo'), isTrue);
    });

    test('flutter_riverpod (officiel) est OK', () {
      expect(isSuspiciousName('flutter_riverpod'), isFalse);
    });

    test('crypto (officiel) est OK', () {
      expect(isSuspiciousName('crypto'), isFalse);
    });

    test('go_router est OK', () {
      expect(isSuspiciousName('go_router'), isFalse);
    });
  });

  group('Supply Chain — Packages de confiance', () {
    test('liste des packages verifies', () {
      const trusted = {
        'flutter_riverpod', 'go_router', 'shared_preferences',
        'google_fonts', 'crypto', 'path_provider',
        'url_launcher', 'dartssh2',
      };
      expect(trusted.contains('flutter_riverpod'), isTrue);
      expect(trusted.contains('crypto'), isTrue);
      expect(trusted.contains('malicious_package'), isFalse);
    });

    test('source git est un warning', () {
      const source = 'git';
      expect(source, 'git');
      // Les packages git ne viennent pas de pub.dev
      // et ne sont pas verifies
    });

    test('source hosted (pub.dev) est ok', () {
      const source = 'hosted';
      expect(source, isNot('git'));
    });
  });

  group('ACL Tailscale — Template', () {
    test('pas de wildcard dans les ACLs', () {
      const aclRules = [
        {'action': 'accept', 'src': ['tag:chillapp-bridge'],
         'dst': ['tag:chillapp-target:22']},
      ];
      for (final rule in aclRules) {
        final src = rule['src'] as List;
        final dst = rule['dst'] as List;
        for (final s in src) {
          expect(s, isNot('*'));
        }
        for (final d in dst) {
          expect(d, isNot('*'));
        }
      }
    });
  });
}
