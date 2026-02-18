// =============================================================
// Tests unitaires — FIX-017 : TailscaleFirewallRules
// Verifie la logique interne sans executer de commandes systeme.
// =============================================================
//
// Executer avec :
//   dart test test/unit/security/test_tailscale_firewall.dart
//
// Ces tests ne lancent AUCUNE commande systeme (pas de pkexec,
// powershell, pfctl...). Ils verifient uniquement :
//   - la validation CIDR et port
//   - les constantes
//   - la generation des scripts (syntaxe de base)
// =============================================================

import 'package:test/test.dart';
import 'package:chill_app/core/security/tailscale_firewall.dart';

void main() {
  // ---------------------------------------------------------------
  // Constantes et configuration de base
  // ---------------------------------------------------------------

  group('TailscaleFirewallRules — constantes', () {
    test('le sous-reseau Tailscale est 100.64.0.0/10', () {
      expect(
        TailscaleFirewallRules.tailscaleSubnet,
        equals('100.64.0.0/10'),
        reason: 'Plage CGNAT Tailscale correcte',
      );
    });

    test('le port SSH par defaut est 22', () {
      final fw = TailscaleFirewallRules();
      expect(fw.sshPort, equals(22));
    });

    test('un port personnalise est accepte', () {
      final fw = TailscaleFirewallRules(sshPort: 2222);
      expect(fw.sshPort, equals(2222));
    });
  });

  // ---------------------------------------------------------------
  // Validation CIDR
  // ---------------------------------------------------------------

  group('isValidCidr', () {
    test('accepte le sous-reseau Tailscale standard', () {
      expect(
        TailscaleFirewallRules.isValidCidr('100.64.0.0/10'),
        isTrue,
      );
    });

    test('accepte une notation CIDR valide quelconque', () {
      expect(TailscaleFirewallRules.isValidCidr('192.168.1.0/24'), isTrue);
      expect(TailscaleFirewallRules.isValidCidr('10.0.0.0/8'), isTrue);
      expect(TailscaleFirewallRules.isValidCidr('0.0.0.0/0'), isTrue);
    });

    test('refuse une IP sans prefixe CIDR', () {
      expect(TailscaleFirewallRules.isValidCidr('192.168.1.1'), isFalse);
    });

    test('refuse une notation avec prefixe invalide', () {
      expect(TailscaleFirewallRules.isValidCidr('192.168.1.0/33'), isFalse);
      expect(TailscaleFirewallRules.isValidCidr('192.168.1.0/-1'), isFalse);
    });

    test('refuse un CIDR avec octets hors plage', () {
      expect(TailscaleFirewallRules.isValidCidr('256.0.0.0/8'), isFalse);
      expect(TailscaleFirewallRules.isValidCidr('192.168.300.0/24'), isFalse);
    });

    test('refuse une chaine vide ou mal formee', () {
      expect(TailscaleFirewallRules.isValidCidr(''), isFalse);
      expect(TailscaleFirewallRules.isValidCidr('abc/def'), isFalse);
      expect(TailscaleFirewallRules.isValidCidr('/24'), isFalse);
    });
  });

  // ---------------------------------------------------------------
  // Validation de port
  // ---------------------------------------------------------------

  group('isValidPort', () {
    test('accepte le port SSH standard (22)', () {
      expect(TailscaleFirewallRules.isValidPort(22), isTrue);
    });

    test('accepte des ports alternatifs valides', () {
      expect(TailscaleFirewallRules.isValidPort(2222), isTrue);
      expect(TailscaleFirewallRules.isValidPort(65535), isTrue);
      expect(TailscaleFirewallRules.isValidPort(1), isTrue);
    });

    test('refuse le port 0', () {
      expect(TailscaleFirewallRules.isValidPort(0), isFalse);
    });

    test('refuse les ports negatifs', () {
      expect(TailscaleFirewallRules.isValidPort(-1), isFalse);
      expect(TailscaleFirewallRules.isValidPort(-100), isFalse);
    });

    test('refuse les ports superieurs a 65535', () {
      expect(TailscaleFirewallRules.isValidPort(65536), isFalse);
      expect(TailscaleFirewallRules.isValidPort(99999), isFalse);
    });
  });

  // ---------------------------------------------------------------
  // Generation de scripts (sans execution)
  // ---------------------------------------------------------------

  group('Scripts generes — syntaxe', () {
    test('le script nftables contient le sous-reseau Tailscale', () {
      final fw = TailscaleFirewallRules();
      final script = fw.buildNftScript();
      expect(
        script.contains(TailscaleFirewallRules.tailscaleSubnet),
        isTrue,
        reason: 'Le script nft doit mentionner 100.64.0.0/10',
      );
    });

    test('le script nftables contient le port SSH', () {
      final fw = TailscaleFirewallRules(sshPort: 22);
      final script = fw.buildNftScript();
      expect(script.contains('22'), isTrue,
          reason: 'Le port SSH doit apparaitre dans le script');
    });

    test('le script Linux contient le fallback UFW', () {
      final fw = TailscaleFirewallRules();
      final script = fw.buildLinuxApplyScript();
      expect(script.contains('ufw'), isTrue,
          reason: 'Le fallback UFW est present dans le script Linux');
    });

    test('le script Linux contient nftables comme methode principale', () {
      final fw = TailscaleFirewallRules();
      final script = fw.buildLinuxApplyScript();
      expect(script.contains('nft'), isTrue,
          reason: 'nftables est la methode principale');
    });

    test('un port personnalise est bien inclus dans le script', () {
      final fw = TailscaleFirewallRules(sshPort: 2222);
      final script = fw.buildNftScript();
      expect(script.contains('2222'), isTrue,
          reason: 'Le port personnalise doit apparaitre dans le script');
    });
  });
}
