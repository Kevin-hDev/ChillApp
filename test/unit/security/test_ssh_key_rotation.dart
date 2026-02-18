// =============================================================
// Tests unitaires : FIX-029 — SshKeyRotation
// =============================================================

import 'dart:io';
import 'package:test/test.dart';
import 'package:chill_app/core/security/ssh_key_rotation.dart';

void main() {
  // ---------------------------------------------------------------------------
  // KeyRotationConfig
  // ---------------------------------------------------------------------------
  group('KeyRotationConfig — valeurs par defaut', () {
    test('maxAgeDays est 30 par defaut', () {
      final config = KeyRotationConfig();
      expect(config.maxAgeDays, equals(30));
    });

    test('algorithm est "ed25519" par defaut', () {
      final config = KeyRotationConfig();
      expect(config.algorithm, equals('ed25519'));
    });

    test('keyBits est 4096 par defaut', () {
      final config = KeyRotationConfig();
      expect(config.keyBits, equals(4096));
    });

    test('sshDir est non vide par defaut', () {
      final config = KeyRotationConfig();
      expect(config.sshDir, isNotEmpty);
    });

    test('sshDir termine par ".ssh"', () {
      final config = KeyRotationConfig();
      expect(config.sshDir, endsWith('.ssh'));
    });

    test('sshDir peut etre personnalise', () {
      final config = KeyRotationConfig(sshDir: '/tmp/test-ssh');
      expect(config.sshDir, equals('/tmp/test-ssh'));
    });
  });

  group('KeyRotationConfig.defaultSshDir', () {
    test('retourne une chaine non vide', () {
      expect(KeyRotationConfig.defaultSshDir, isNotEmpty);
    });

    test('contient ".ssh"', () {
      expect(KeyRotationConfig.defaultSshDir, contains('.ssh'));
    });
  });

  // ---------------------------------------------------------------------------
  // RotationCheckResult
  // ---------------------------------------------------------------------------
  group('RotationCheckResult — proprietes', () {
    test('needsRotation est correctement stocke', () {
      const result = RotationCheckResult(
        needsRotation: true,
        keyPath: '/home/user/.ssh/id_ed25519',
        reason: 'Cle trop ancienne',
      );
      expect(result.needsRotation, isTrue);
    });

    test('keyAgeDays est optionnel (null si cle absente)', () {
      const result = RotationCheckResult(
        needsRotation: true,
        keyPath: '/home/user/.ssh/id_ed25519',
        reason: 'Cle introuvable',
      );
      expect(result.keyAgeDays, isNull);
    });

    test('keyAgeDays est renseigne quand la cle existe', () {
      const result = RotationCheckResult(
        needsRotation: false,
        keyPath: '/home/user/.ssh/id_ed25519',
        reason: 'Cle valide',
        keyAgeDays: 15,
      );
      expect(result.keyAgeDays, equals(15));
    });
  });

  // ---------------------------------------------------------------------------
  // RotationResult — proprietes
  // ---------------------------------------------------------------------------
  group('RotationResult — proprietes', () {
    test('success=false avec message d\'erreur', () {
      const result = RotationResult(
        success: false,
        error: 'ssh-keygen non trouve',
      );
      expect(result.success, isFalse);
      expect(result.error, equals('ssh-keygen non trouve'));
      expect(result.newKeyPath, isNull);
      expect(result.oldKeyBackupPath, isNull);
    });

    test('success=true avec chemins de cle', () {
      const result = RotationResult(
        success: true,
        newKeyPath: '/home/user/.ssh/id_ed25519',
        oldKeyBackupPath: '/home/user/.ssh/id_ed25519.old',
      );
      expect(result.success, isTrue);
      expect(result.newKeyPath, equals('/home/user/.ssh/id_ed25519'));
      expect(
        result.oldKeyBackupPath,
        equals('/home/user/.ssh/id_ed25519.old'),
      );
      expect(result.error, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // checkRotationNeeded — tests sans reseau ni SSH
  // ---------------------------------------------------------------------------
  group('SshKeyRotation — checkRotationNeeded()', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chill-ssh-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('retourne needsRotation=true quand la cle n\'existe pas', () async {
      final config = KeyRotationConfig(sshDir: tempDir.path, maxAgeDays: 30);
      final rotation = SshKeyRotation(config: config);

      final result = await rotation.checkRotationNeeded('id_ed25519');
      expect(result.needsRotation, isTrue);
      expect(result.keyAgeDays, isNull);
      expect(result.reason, contains('introuvable'));
    });

    test('retourne needsRotation=false pour une cle recemment creee', () async {
      // Creer un fichier cle fictif avec la date actuelle
      final keyFile = File('${tempDir.path}/id_ed25519');
      await keyFile.writeAsString('-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n');

      final config = KeyRotationConfig(sshDir: tempDir.path, maxAgeDays: 30);
      final rotation = SshKeyRotation(config: config);

      final result = await rotation.checkRotationNeeded('id_ed25519');
      expect(result.needsRotation, isFalse);
      expect(result.keyAgeDays, isNotNull);
      expect(result.keyAgeDays, lessThan(30));
      expect(result.reason, contains('valide'));
    });

    test('le chemin de cle est correctement construit', () async {
      final config = KeyRotationConfig(
        sshDir: '/home/user/.ssh',
        maxAgeDays: 30,
      );
      final rotation = SshKeyRotation(config: config);

      final result = await rotation.checkRotationNeeded('id_ed25519');
      expect(result.keyPath, equals('/home/user/.ssh/id_ed25519'));
    });

    test('retourne needsRotation=true quand l\'age >= maxAgeDays', () async {
      // Verifier la logique : age 30 jours avec limite 30 doit declencher
      // En pratique, on ne peut pas forcer la date de modification d'un fichier
      // sans des commandes systeme. On teste donc la logique via un seuil de 0 jour.
      final keyFile = File('${tempDir.path}/id_ed25519');
      await keyFile.writeAsString('fake-key-content');

      // Avec maxAgeDays=0, n'importe quelle cle doit etre rotee
      final config = KeyRotationConfig(sshDir: tempDir.path, maxAgeDays: 0);
      final rotation = SshKeyRotation(config: config);

      final result = await rotation.checkRotationNeeded('id_ed25519');
      expect(result.needsRotation, isTrue);
      expect(result.reason, contains('agee'));
    });
  });

  // ---------------------------------------------------------------------------
  // shellEscape — methode statique publique
  // ---------------------------------------------------------------------------
  group('SshKeyRotation — shellEscape()', () {
    test('ne modifie pas une chaine sans guillemets simples', () {
      expect(
        SshKeyRotation.shellEscape('cle sans guillemets'),
        equals('cle sans guillemets'),
      );
    });

    test('echappe les guillemets simples correctement', () {
      // Le pattern standard d'echappement shell : ' -> '\''
      final result = SshKeyRotation.shellEscape("ssh-ed25519 AAAA it's a key");
      expect(result, contains("'\\''"));
    });

    test('echappe plusieurs guillemets simples dans la meme chaine', () {
      final result = SshKeyRotation.shellEscape("a'b'c");
      expect(result, equals("a'\\''b'\\''c"));
    });

    test('retourne une chaine vide si l\'entree est vide', () {
      expect(SshKeyRotation.shellEscape(''), equals(''));
    });

    test('une cle SSH typique sans guillemet reste inchangee', () {
      const typicalKey =
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI comment@host';
      expect(SshKeyRotation.shellEscape(typicalKey), equals(typicalKey));
    });
  });
}
