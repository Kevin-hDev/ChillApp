// Test unitaire pour FIX-036 — SshdHardening
// Lance avec : flutter test test/unit/security/test_sshd_hardening.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/sshd_hardening.dart';

void main() {
  late SshdHardening hardening;

  setUp(() {
    hardening = SshdHardening();
  });

  // ===========================================================
  // auditConfig — détection des problèmes
  // ===========================================================

  group('auditConfig — détection des problèmes critiques', () {
    test('détecte PermitRootLogin yes comme problème critique', () {
      const badConfig = '''
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms curve25519-sha256
Ciphers aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com
LogLevel VERBOSE
''';
      final results = hardening.auditConfig(badConfig);
      final rootLogin = results.firstWhere(
        (r) => r.parameter == 'PermitRootLogin',
      );
      expect(rootLogin.isCompliant, isFalse);
      expect(rootLogin.severity, equals('critical'));
    });

    test('détecte PasswordAuthentication yes comme problème critique', () {
      const badConfig = '''
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms curve25519-sha256
Ciphers aes256-gcm@openssh.com
''';
      final results = hardening.auditConfig(badConfig);
      final passAuth = results.firstWhere(
        (r) => r.parameter == 'PasswordAuthentication',
      );
      expect(passAuth.isCompliant, isFalse);
      expect(passAuth.severity, equals('critical'));
    });

    test('détecte les algorithmes KEX faibles (SHA-1)', () {
      const badConfig = '''
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
Ciphers aes256-gcm@openssh.com
''';
      final results = hardening.auditConfig(badConfig);
      final kex = results.firstWhere((r) => r.parameter == 'KexAlgorithms');
      expect(kex.isCompliant, isFalse);
      expect(kex.severity, equals('critical'));
    });

    test('détecte les ciphers CBC comme problème critique', () {
      const badConfig = '''
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms curve25519-sha256
Ciphers aes128-cbc,aes256-cbc,3des-cbc
''';
      final results = hardening.auditConfig(badConfig);
      final ciphers = results.firstWhere((r) => r.parameter == 'Ciphers');
      expect(ciphers.isCompliant, isFalse);
      expect(ciphers.severity, equals('critical'));
    });

    test('une bonne configuration est conforme (pas de critiques)', () {
      const goodConfig = '''
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
StrictModes yes
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
LogLevel VERBOSE
''';
      final results = hardening.auditConfig(goodConfig);
      expect(hardening.hasCriticalIssues(results), isFalse);
    });

    test('les commentaires sont ignorés lors du parsing', () {
      const configWithComments = '''
# Ceci est un commentaire
PermitRootLogin no
# Un autre commentaire
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms curve25519-sha256
Ciphers aes256-gcm@openssh.com
''';
      final results = hardening.auditConfig(configWithComments);
      final rootLogin = results.firstWhere(
        (r) => r.parameter == 'PermitRootLogin',
      );
      // Doit être conforme malgré les commentaires
      expect(rootLogin.isCompliant, isTrue);
    });
  });

  // ===========================================================
  // generateHardenedConfig
  // ===========================================================

  group('generateHardenedConfig', () {
    test('le template contient PermitRootLogin no', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('PermitRootLogin no'));
    });

    test('le template contient PasswordAuthentication no', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('PasswordAuthentication no'));
    });

    test('le template contient PubkeyAuthentication yes', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('PubkeyAuthentication yes'));
    });

    test('le template contient curve25519-sha256 (KEX moderne)', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('curve25519-sha256'));
    });

    test('le template contient aes256-gcm (cipher sécurisé)', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('aes256-gcm@openssh.com'));
    });

    test('le template contient chacha20-poly1305', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('chacha20-poly1305@openssh.com'));
    });

    test('le template contient hmac-sha2-512-etm (MAC ETM)', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('hmac-sha2-512-etm@openssh.com'));
    });

    test('le template ne contient pas de modes CBC', () {
      final template = hardening.generateHardenedConfig();
      expect(template, isNot(contains('aes128-cbc')));
      expect(template, isNot(contains('aes256-cbc')));
      expect(template, isNot(contains('3des-cbc')));
    });

    test('le template contient le réseau Tailscale AllowUsers', () {
      final template = hardening.generateHardenedConfig();
      expect(template, contains('100.64.0.0/10'));
    });

    test('la configuration custom est appliquée au template', () {
      final customHardening = SshdHardening(
        config: const SshdHardeningConfig(
          port: 2222,
          maxAuthTries: 2,
        ),
      );
      final template = customHardening.generateHardenedConfig();
      expect(template, contains('Port 2222'));
      expect(template, contains('MaxAuthTries 2'));
    });
  });

  // ===========================================================
  // hasCriticalIssues
  // ===========================================================

  group('hasCriticalIssues', () {
    test('retourne true si un problème critique est présent', () {
      const badConfig = 'PermitRootLogin yes\nPasswordAuthentication yes\n';
      final results = hardening.auditConfig(badConfig);
      expect(hardening.hasCriticalIssues(results), isTrue);
    });

    test('retourne false si aucun problème critique (seulement warnings)', () {
      // Config avec les critiques OK mais quelques warnings
      const warningOnlyConfig = '''
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms curve25519-sha256
Ciphers aes256-gcm@openssh.com
X11Forwarding yes
LogLevel INFO
''';
      final results = hardening.auditConfig(warningOnlyConfig);
      expect(hardening.hasCriticalIssues(results), isFalse);
    });

    test('retourne false pour une liste vide', () {
      expect(hardening.hasCriticalIssues([]), isFalse);
    });
  });
}
