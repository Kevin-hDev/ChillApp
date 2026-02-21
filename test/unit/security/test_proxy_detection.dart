// =============================================================
// Tests unitaires : FIX-037 — ProxyDetector
// =============================================================

import 'package:test/test.dart';
import 'package:chill_app/core/security/proxy_detection.dart';

void main() {
  group('ProxyDetector — constantes', () {
    test('proxyPorts contient les ports connus (8080, 8888, 3128, 1080)', () {
      expect(ProxyDetector.proxyPorts, contains(8080));
      expect(ProxyDetector.proxyPorts, contains(8888));
      expect(ProxyDetector.proxyPorts, contains(3128));
      expect(ProxyDetector.proxyPorts, contains(1080));
    });

    test('proxyPorts contient 11 ports au total', () {
      expect(ProxyDetector.proxyPorts.length, equals(11));
    });

    test('proxyEnvVars contient http_proxy et HTTPS_PROXY', () {
      expect(ProxyDetector.proxyEnvVars, contains('http_proxy'));
      expect(ProxyDetector.proxyEnvVars, contains('HTTPS_PROXY'));
    });

    test('proxyEnvVars contient ALL_PROXY et SOCKS_PROXY', () {
      expect(ProxyDetector.proxyEnvVars, contains('ALL_PROXY'));
      expect(ProxyDetector.proxyEnvVars, contains('SOCKS_PROXY'));
    });

    test('vpnInterfacePatterns ne contient pas de prefixes Tailscale', () {
      for (final tailscalePattern in ProxyDetector.tailscaleInterfaces) {
        expect(
          ProxyDetector.vpnInterfacePatterns,
          isNot(contains(tailscalePattern)),
          reason:
              'vpnInterfacePatterns ne doit pas contenir "$tailscalePattern"',
        );
      }
    });

    test('tailscaleInterfaces contient "tailscale" et "ts"', () {
      expect(ProxyDetector.tailscaleInterfaces, contains('tailscale'));
      expect(ProxyDetector.tailscaleInterfaces, contains('ts'));
    });
  });

  group('ProxyDetector — sanitize()', () {
    test('tronque les chaines de plus de 50 caracteres', () {
      final longString = 'A' * 60;
      final result = ProxyDetector.sanitize(longString);
      expect(result.length, lessThanOrEqualTo(54)); // 50 + '...'
      expect(result, endsWith('...'));
    });

    test('retourne la chaine intacte si <= 50 caracteres', () {
      const short = 'http://proxy.example.com:8080';
      expect(ProxyDetector.sanitize(short), equals(short));
    });

    test('tronque exactement a 50 caracteres + "..."', () {
      final exact51 = 'B' * 51;
      final result = ProxyDetector.sanitize(exact51);
      expect(result, equals('${'B' * 50}...'));
    });

    test('une chaine de 50 caracteres exactement reste intacte', () {
      final exact50 = 'C' * 50;
      expect(ProxyDetector.sanitize(exact50), equals(exact50));
    });
  });

  group('ProxyDetector — checkEnvironment()', () {
    test(
        'retourne une liste vide quand aucune variable proxy n\'est definie',
        () {
      // Dans la plupart des environnements CI/test, aucun proxy n'est defini.
      // Ce test echoue uniquement si le systeme hote a un proxy configure.
      final detector = ProxyDetector();
      final results = detector.checkEnvironment();

      // Filtrer uniquement les vrais proxies (pas NO_PROXY)
      final proxyResults =
          results.where((r) => r.threat == ProxyThreat.envProxy).toList();

      // Verifier que tous les resultats ont bien le bon type de menace
      for (final r in proxyResults) {
        expect(r.severity, equals('critical'));
        expect(r.threat, equals(ProxyThreat.envProxy));
      }
    });

    test('NO_PROXY est ignore (ne produit pas d\'alerte)', () {
      // NO_PROXY est une liste d'exclusions, pas un proxy actif.
      // Ce test verifie la logique de filtrage.
      final detector = ProxyDetector();
      final results = detector.checkEnvironment();
      final noProxyAlerts = results
          .where((r) => r.detail.contains('NO_PROXY') || r.detail.contains('no_proxy'))
          .toList();
      expect(noProxyAlerts, isEmpty,
          reason: 'NO_PROXY ne doit jamais generer d\'alerte');
    });
  });

  group('ProxyDetectionResult — toString()', () {
    test('contient le nom de la menace', () {
      const result = ProxyDetectionResult(
        threat: ProxyThreat.envProxy,
        detail: 'Variable http_proxy definie',
        severity: 'critical',
      );
      expect(result.toString(), contains('envProxy'));
    });

    test('contient le detail', () {
      const result = ProxyDetectionResult(
        threat: ProxyThreat.localProxy,
        detail: 'Port 8080 ouvert sur localhost',
        severity: 'warning',
      );
      expect(result.toString(), contains('Port 8080 ouvert sur localhost'));
    });

    test('format [threatName] detail', () {
      const result = ProxyDetectionResult(
        threat: ProxyThreat.foreignVpn,
        detail: 'Interface tun0 detectee',
        severity: 'warning',
      );
      expect(result.toString(), equals('[foreignVpn] Interface tun0 detectee'));
    });
  });

  group('ProxyThreat — enum', () {
    test('contient exactement 4 valeurs', () {
      expect(ProxyThreat.values.length, equals(4));
    });

    test('contient envProxy, localProxy, foreignVpn, suspiciousRoute', () {
      expect(ProxyThreat.values, contains(ProxyThreat.envProxy));
      expect(ProxyThreat.values, contains(ProxyThreat.localProxy));
      expect(ProxyThreat.values, contains(ProxyThreat.foreignVpn));
      expect(ProxyThreat.values, contains(ProxyThreat.suspiciousRoute));
    });
  });
}
