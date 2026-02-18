// =============================================================
// Tests unitaires — FIX-014 : DaemonIntegrity
// Verifier l'integrite du binaire daemon via SHA-256
// =============================================================
//
// Executer avec :
//   dart test test/unit/security/test_daemon_integrity.dart
//
// =============================================================

import 'dart:io';
import 'package:test/test.dart';
import 'package:chill_app/core/security/daemon_integrity.dart';

void main() {
  // Dossier temporaire utilise pour tous les tests de ce fichier
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('daemon_integrity_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------
  // verifyBinary — cas normaux
  // ---------------------------------------------------------------

  group('verifyBinary', () {
    test('retourne true quand le hash correspond', () async {
      // Creer un faux binaire
      final bin = File('${tempDir.path}/fake_daemon');
      await bin.writeAsBytes([0x7F, 0x45, 0x4C, 0x46, 0xDE, 0xAD]); // faux ELF

      // Generer le fichier .sha256 de reference
      await DaemonIntegrity.generateHashFile(bin.path);

      // Verifier : doit etre valide
      final result = await DaemonIntegrity.verifyBinary(bin.path);
      expect(result, isTrue, reason: 'Hash correct => verifyBinary = true');
    });

    test('retourne false si le binaire a ete modifie', () async {
      // Creer le binaire + son .sha256 d'origine
      final bin = File('${tempDir.path}/fake_daemon');
      await bin.writeAsBytes([0xCA, 0xFE, 0xBA, 0xBE]);
      await DaemonIntegrity.generateHashFile(bin.path);

      // Modifier le binaire APRES avoir genere le hash
      await bin.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF]);

      // Verifier : doit detecter la corruption
      final result = await DaemonIntegrity.verifyBinary(bin.path);
      expect(result, isFalse, reason: 'Binaire modifie => verifyBinary = false');
    });

    test('retourne false si le binaire est absent', () async {
      final binaryPath = '${tempDir.path}/nonexistent_binary';
      final result = await DaemonIntegrity.verifyBinary(binaryPath);
      expect(result, isFalse, reason: 'Binaire absent => false');
    });

    test('retourne false si le fichier .sha256 est absent', () async {
      // Binaire present MAIS pas de .sha256
      final bin = File('${tempDir.path}/daemon_no_hash');
      await bin.writeAsBytes([0x01, 0x02, 0x03]);

      final result = await DaemonIntegrity.verifyBinary(bin.path);
      expect(result, isFalse, reason: 'Fichier .sha256 absent => false');
    });

    test('retourne false si le fichier .sha256 est vide', () async {
      final bin = File('${tempDir.path}/daemon_empty_hash');
      await bin.writeAsBytes([0x01]);

      final hashFile = File('${bin.path}.sha256');
      await hashFile.writeAsString('');

      final result = await DaemonIntegrity.verifyBinary(bin.path);
      expect(result, isFalse, reason: 'Fichier .sha256 vide => false');
    });

    test('retourne false si le fichier .sha256 contient un hash invalide', () async {
      final bin = File('${tempDir.path}/daemon_bad_hash');
      await bin.writeAsBytes([0x01, 0x02]);

      final hashFile = File('${bin.path}.sha256');
      // Hash trop court (pas 64 hex)
      await hashFile.writeAsString('deadbeef');

      final result = await DaemonIntegrity.verifyBinary(bin.path);
      expect(result, isFalse, reason: 'Hash invalide (< 64 chars) => false');
    });

    test('retourne false si le hash est celui d un autre fichier', () async {
      // Creer deux binaires differents
      final bin1 = File('${tempDir.path}/daemon_a');
      final bin2 = File('${tempDir.path}/daemon_b');
      await bin1.writeAsBytes([0xAA, 0xBB, 0xCC]);
      await bin2.writeAsBytes([0x11, 0x22, 0x33]);

      // Generer le .sha256 de bin2
      await DaemonIntegrity.generateHashFile(bin2.path);

      // Copier le .sha256 de bin2 vers bin1 (hash errone)
      final hash2 = File('${bin2.path}.sha256');
      final hash1 = File('${bin1.path}.sha256');
      await hash1.writeAsString(await hash2.readAsString());

      // Verifier bin1 avec le .sha256 de bin2 : doit echouer
      final result = await DaemonIntegrity.verifyBinary(bin1.path);
      expect(result, isFalse, reason: 'Hash d un autre fichier => false');
    });
  });

  // ---------------------------------------------------------------
  // generateHashFile
  // ---------------------------------------------------------------

  group('generateHashFile', () {
    test('cree un fichier .sha256 contenant 64 caracteres hex', () async {
      final bin = File('${tempDir.path}/bin_generate');
      await bin.writeAsBytes(List.generate(256, (i) => i));

      await DaemonIntegrity.generateHashFile(bin.path);

      final hashFile = File('${bin.path}.sha256');
      expect(await hashFile.exists(), isTrue, reason: 'Fichier .sha256 cree');

      final content = (await hashFile.readAsString()).trim();
      expect(content.length, equals(64), reason: 'Hash SHA-256 = 64 hex');
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(content),
        isTrue,
        reason: 'Contient uniquement des caracteres hexadecimaux',
      );
    });

    test('le hash genere correspond a celui de computeHash', () async {
      final bin = File('${tempDir.path}/bin_compare');
      await bin.writeAsBytes([0xFF, 0xFE, 0xFD, 0xFC]);

      await DaemonIntegrity.generateHashFile(bin.path);
      final hashFile = File('${bin.path}.sha256');
      final storedHash = (await hashFile.readAsString()).trim();

      final computedHash = await DaemonIntegrity.computeHash(bin.path);
      expect(storedHash, equals(computedHash), reason: 'Hash stocke = hash calcule');
    });

    test('lance une exception si le binaire est absent', () async {
      expect(
        () => DaemonIntegrity.generateHashFile('/tmp/inexistant_xyz_abc'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  // ---------------------------------------------------------------
  // computeHash — proprietes cryptographiques
  // ---------------------------------------------------------------

  group('computeHash', () {
    test('le hash est deterministe (meme contenu => meme hash)', () async {
      final bin = File('${tempDir.path}/bin_deterministe');
      await bin.writeAsBytes([0x01, 0x02, 0x03]);

      final hash1 = await DaemonIntegrity.computeHash(bin.path);
      final hash2 = await DaemonIntegrity.computeHash(bin.path);
      expect(hash1, equals(hash2), reason: 'Hash deterministe');
    });

    test('contenus differents produisent des hash differents', () async {
      final a = File('${tempDir.path}/content_a');
      final b = File('${tempDir.path}/content_b');
      await a.writeAsBytes([0x00]);
      await b.writeAsBytes([0xFF]);

      final hashA = await DaemonIntegrity.computeHash(a.path);
      final hashB = await DaemonIntegrity.computeHash(b.path);
      expect(hashA, isNot(equals(hashB)), reason: 'Contenus differents => hash differents');
    });
  });
}
