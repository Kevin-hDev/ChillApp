// Test unitaire pour FIX-033 — SshHardenedAlgorithms
// Lance avec : flutter test test/unit/security/test_ssh_hardened.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/ssh_hardened_config.dart';

void main() {
  // ============================================================
  // SshHardenedAlgorithms — listes
  // ============================================================

  group('SshHardenedAlgorithms — whitelist', () {
    test('allowedKex contient curve25519-sha256', () {
      expect(SshHardenedAlgorithms.allowedKex, contains('curve25519-sha256'));
    });

    test('allowedKex contient les variantes ecdh-sha2-nistp*', () {
      expect(SshHardenedAlgorithms.allowedKex,
          contains('ecdh-sha2-nistp256'));
      expect(SshHardenedAlgorithms.allowedKex,
          contains('ecdh-sha2-nistp384'));
      expect(SshHardenedAlgorithms.allowedKex,
          contains('ecdh-sha2-nistp521'));
    });

    test('allowedKex contient DH group16/18-sha512', () {
      expect(SshHardenedAlgorithms.allowedKex,
          contains('diffie-hellman-group16-sha512'));
      expect(SshHardenedAlgorithms.allowedKex,
          contains('diffie-hellman-group18-sha512'));
    });

    test('allowedHostKeys contient ssh-ed25519', () {
      expect(SshHardenedAlgorithms.allowedHostKeys, contains('ssh-ed25519'));
    });

    test('allowedHostKeys contient rsa-sha2-256 et rsa-sha2-512', () {
      expect(SshHardenedAlgorithms.allowedHostKeys, contains('rsa-sha2-256'));
      expect(SshHardenedAlgorithms.allowedHostKeys, contains('rsa-sha2-512'));
    });

    test('allowedCiphers contient aes256-gcm@openssh.com', () {
      expect(SshHardenedAlgorithms.allowedCiphers,
          contains('aes256-gcm@openssh.com'));
    });

    test('allowedCiphers contient chacha20-poly1305@openssh.com', () {
      expect(SshHardenedAlgorithms.allowedCiphers,
          contains('chacha20-poly1305@openssh.com'));
    });

    test('allowedCiphers ne contient aucun mode CBC', () {
      for (final cipher in SshHardenedAlgorithms.allowedCiphers) {
        expect(cipher, isNot(contains('-cbc')),
            reason: 'CBC interdit (Terrapin CVE-2023-48795)');
      }
    });

    test('allowedMacs contient les variantes ETM SHA-2', () {
      expect(SshHardenedAlgorithms.allowedMacs,
          contains('hmac-sha2-256-etm@openssh.com'));
      expect(SshHardenedAlgorithms.allowedMacs,
          contains('hmac-sha2-512-etm@openssh.com'));
    });

    test('allowedMacs ne contient pas hmac-sha1 ni hmac-md5', () {
      expect(SshHardenedAlgorithms.allowedMacs,
          isNot(contains('hmac-sha1')));
      expect(SshHardenedAlgorithms.allowedMacs,
          isNot(contains('hmac-md5')));
    });
  });

  // ============================================================
  // Blacklist — 19 algorithmes dangereux
  // ============================================================

  group('SshHardenedAlgorithms — blacklist (19 algorithmes)', () {
    final expectedBlacklisted = [
      // KEX faibles
      'diffie-hellman-group1-sha1',
      'diffie-hellman-group14-sha1',
      'diffie-hellman-group-exchange-sha1',
      // Host keys faibles
      'ssh-rsa',
      'ssh-dss',
      // Ciphers CBC
      'aes128-cbc',
      'aes192-cbc',
      'aes256-cbc',
      '3des-cbc',
      'blowfish-cbc',
      'cast128-cbc',
      // RC4
      'arcfour',
      'arcfour128',
      'arcfour256',
      // MACs faibles
      'hmac-sha1',
      'hmac-sha1-96',
      'hmac-md5',
      'hmac-md5-96',
      'umac-64@openssh.com',
    ];

    test('blacklist contient exactement 19 algorithmes', () {
      expect(SshHardenedAlgorithms.blacklisted.length, 19);
    });

    for (final algo in expectedBlacklisted) {
      test('blacklist contient "$algo"', () {
        expect(SshHardenedAlgorithms.blacklisted, contains(algo));
      });
    }
  });

  // ============================================================
  // isAlgorithmAllowed
  // ============================================================

  group('isAlgorithmAllowed', () {
    test('curve25519-sha256 est autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('curve25519-sha256'),
          isTrue);
    });

    test('ssh-ed25519 est autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('ssh-ed25519'), isTrue);
    });

    test('aes256-gcm@openssh.com est autorise', () {
      expect(
          SshHardenedAlgorithms.isAlgorithmAllowed('aes256-gcm@openssh.com'),
          isTrue);
    });

    test('hmac-sha2-256 est autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('hmac-sha2-256'),
          isTrue);
    });

    test('diffie-hellman-group1-sha1 n\'est pas autorise', () {
      expect(
          SshHardenedAlgorithms.isAlgorithmAllowed(
              'diffie-hellman-group1-sha1'),
          isFalse);
    });

    test('ssh-rsa n\'est pas autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('ssh-rsa'), isFalse);
    });

    test('aes128-cbc n\'est pas autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('aes128-cbc'), isFalse);
    });

    test('hmac-sha1 n\'est pas autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('hmac-sha1'), isFalse);
    });

    test('algorithme inconnu n\'est pas autorise', () {
      expect(SshHardenedAlgorithms.isAlgorithmAllowed('algo-inconnu'),
          isFalse);
    });
  });

  // ============================================================
  // isAlgorithmBlacklisted
  // ============================================================

  group('isAlgorithmBlacklisted', () {
    test('ssh-rsa est blackliste', () {
      expect(SshHardenedAlgorithms.isAlgorithmBlacklisted('ssh-rsa'), isTrue);
    });

    test('hmac-md5 est blackliste', () {
      expect(SshHardenedAlgorithms.isAlgorithmBlacklisted('hmac-md5'), isTrue);
    });

    test('arcfour est blackliste', () {
      expect(SshHardenedAlgorithms.isAlgorithmBlacklisted('arcfour'), isTrue);
    });

    test('curve25519-sha256 n\'est pas blackliste', () {
      expect(
          SshHardenedAlgorithms.isAlgorithmBlacklisted('curve25519-sha256'),
          isFalse);
    });

    test('aes256-gcm@openssh.com n\'est pas blackliste', () {
      expect(
          SshHardenedAlgorithms.isAlgorithmBlacklisted(
              'aes256-gcm@openssh.com'),
          isFalse);
    });
  });

  // ============================================================
  // filterAlgorithms
  // ============================================================

  group('filterAlgorithms', () {
    test('filtre et ne garde que les algo autorises', () {
      final mixed = [
        'curve25519-sha256',
        'diffie-hellman-group1-sha1', // blackliste
        'ssh-ed25519',
        'ssh-rsa', // blackliste
        'aes256-gcm@openssh.com',
        'aes128-cbc', // blackliste
        'hmac-sha2-256',
        'hmac-md5', // blackliste
      ];

      final filtered = SshHardenedAlgorithms.filterAlgorithms(mixed);

      expect(filtered, contains('curve25519-sha256'));
      expect(filtered, contains('ssh-ed25519'));
      expect(filtered, contains('aes256-gcm@openssh.com'));
      expect(filtered, contains('hmac-sha2-256'));

      expect(filtered, isNot(contains('diffie-hellman-group1-sha1')));
      expect(filtered, isNot(contains('ssh-rsa')));
      expect(filtered, isNot(contains('aes128-cbc')));
      expect(filtered, isNot(contains('hmac-md5')));
    });

    test('retourne une liste vide si aucun algo autorise', () {
      final dangerous = [
        'diffie-hellman-group1-sha1',
        'ssh-rsa',
        'aes128-cbc',
        'hmac-sha1',
      ];
      expect(SshHardenedAlgorithms.filterAlgorithms(dangerous), isEmpty);
    });

    test('retourne tous les elements si tous sont autorises', () {
      final safe = [
        'curve25519-sha256',
        'ssh-ed25519',
        'aes256-gcm@openssh.com',
        'hmac-sha2-256',
      ];
      expect(SshHardenedAlgorithms.filterAlgorithms(safe).length, 4);
    });
  });

  // ============================================================
  // SshConfigValidator.validateServer
  // ============================================================

  group('SshConfigValidator.validateServer', () {
    test('serveur avec tous les bons algos est valide', () {
      final result = SshConfigValidator.validateServer(
        serverKex: ['curve25519-sha256', 'ecdh-sha2-nistp256'],
        serverHostKeys: ['ssh-ed25519', 'rsa-sha2-256'],
        serverCiphers: ['aes256-gcm@openssh.com', 'chacha20-poly1305@openssh.com'],
        serverMacs: ['hmac-sha2-256-etm@openssh.com', 'hmac-sha2-512'],
      );
      expect(result.isSecure, isTrue);
      expect(result.issues, isEmpty);
    });

    test('serveur sans KEX securise est invalide', () {
      final result = SshConfigValidator.validateServer(
        serverKex: ['diffie-hellman-group1-sha1'], // blackliste
        serverHostKeys: ['ssh-ed25519'],
        serverCiphers: ['aes256-gcm@openssh.com'],
        serverMacs: ['hmac-sha2-256'],
      );
      expect(result.isSecure, isFalse);
      expect(result.issues.length, greaterThanOrEqualTo(1));
    });

    test('serveur sans cipher securise est invalide', () {
      final result = SshConfigValidator.validateServer(
        serverKex: ['curve25519-sha256'],
        serverHostKeys: ['ssh-ed25519'],
        serverCiphers: ['aes128-cbc', '3des-cbc'], // CBC blackliste
        serverMacs: ['hmac-sha2-256'],
      );
      expect(result.isSecure, isFalse);
    });

    test('detecte les algorithmes dangereux proposes', () {
      final result = SshConfigValidator.validateServer(
        serverKex: ['curve25519-sha256', 'diffie-hellman-group1-sha1'],
        serverHostKeys: ['ssh-ed25519', 'ssh-rsa'],
        serverCiphers: ['aes256-gcm@openssh.com', 'aes128-cbc'],
        serverMacs: ['hmac-sha2-256', 'hmac-md5'],
      );
      // Le serveur est OK (a des algos surs) mais propose aussi des dangereux
      expect(result.isSecure, isTrue);
      expect(result.dangerousAlgorithmsOffered, isNotEmpty);
      expect(result.dangerousAlgorithmsOffered,
          containsAll(['diffie-hellman-group1-sha1', 'ssh-rsa', 'aes128-cbc', 'hmac-md5']));
    });

    test('serveur entierement dangerous est invalide avec toutes les issues', () {
      final result = SshConfigValidator.validateServer(
        serverKex: ['diffie-hellman-group1-sha1'],
        serverHostKeys: ['ssh-rsa'],
        serverCiphers: ['aes128-cbc'],
        serverMacs: ['hmac-sha1'],
      );
      expect(result.isSecure, isFalse);
      expect(result.issues.length, 4);
    });
  });

  // ============================================================
  // RekeyConfig
  // ============================================================

  group('RekeyConfig', () {
    test('valeurs par defaut correctes', () {
      const config = RekeyConfig();
      expect(config.maxBytes, 1073741824); // 1 Go
      expect(config.maxSeconds, 3600); // 1 heure
    });

    test('valeurs personnalisees', () {
      const config = RekeyConfig(maxBytes: 500000000, maxSeconds: 1800);
      expect(config.maxBytes, 500000000);
      expect(config.maxSeconds, 1800);
    });
  });
}
