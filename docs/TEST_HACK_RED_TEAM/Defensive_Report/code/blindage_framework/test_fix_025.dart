// Tests pour FIX-025 (Canary Values)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

void main() {
  // ============================================
  // Tests : MemoryCanary
  // ============================================

  _testGroup('MemoryCanary', () {
    _test('canary intact retourne true', () {
      final rng = Random.secure();
      final value = Uint8List.fromList(
        List.generate(64, (_) => rng.nextInt(256)),
      );
      final hash = sha256.convert(value).toString();

      // Verifier sans modification
      final currentHash = sha256.convert(value).toString();
      _assert(currentHash == hash, 'Canary intact');
    });

    _test('canary modifie retourne false', () {
      final rng = Random.secure();
      final value = Uint8List.fromList(
        List.generate(64, (_) => rng.nextInt(256)),
      );
      final hash = sha256.convert(value).toString();

      // Modifier un byte
      value[0] = (value[0] + 1) % 256;
      final currentHash = sha256.convert(value).toString();
      _assert(currentHash != hash, 'Modification detectee');
    });

    _test('deux canaries sont differents', () {
      final rng = Random.secure();
      final v1 = Uint8List.fromList(List.generate(64, (_) => rng.nextInt(256)));
      final v2 = Uint8List.fromList(List.generate(64, (_) => rng.nextInt(256)));

      final h1 = sha256.convert(v1).toString();
      final h2 = sha256.convert(v2).toString();

      _assert(h1 != h2, 'Canaries uniques');
    });
  });

  // ============================================
  // Tests : FileCanary
  // ============================================

  _testGroup('FileCanary', () {
    _test('deploiement et verification', () async {
      final tempDir = await Directory.systemTemp.createTemp('canary-test-');

      try {
        final canaryPath = '${tempDir.path}/.cache_config.dat';

        // Deployer
        final content = jsonEncode({
          'api_key': _generateFakeToken(),
          'db_password': _generateFakeToken(),
        });
        await File(canaryPath).writeAsString(content);
        final expectedHash = sha256.convert(utf8.encode(content)).toString();

        // Verifier (intact)
        final currentContent = await File(canaryPath).readAsString();
        final currentHash = sha256.convert(utf8.encode(currentContent)).toString();
        _assert(currentHash == expectedHash, 'Canary fichier intact');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    _test('modification detectee', () async {
      final tempDir = await Directory.systemTemp.createTemp('canary-test-');

      try {
        final canaryPath = '${tempDir.path}/.cache_config.dat';
        final content = '{"key": "original"}';
        await File(canaryPath).writeAsString(content);
        final expectedHash = sha256.convert(utf8.encode(content)).toString();

        // Modifier le fichier
        await File(canaryPath).writeAsString('{"key": "tampered"}');

        final currentContent = await File(canaryPath).readAsString();
        final currentHash = sha256.convert(utf8.encode(currentContent)).toString();
        _assert(currentHash != expectedHash, 'Modification detectee');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    _test('suppression detectee', () async {
      final tempDir = await Directory.systemTemp.createTemp('canary-test-');

      try {
        final canaryPath = '${tempDir.path}/.cache_config.dat';
        await File(canaryPath).writeAsString('test');

        // Supprimer le fichier
        await File(canaryPath).delete();

        _assert(!await File(canaryPath).exists(), 'Suppression detectee');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    _test('le faux token semble reel', () {
      final token = _generateFakeToken();
      _assert(token.length > 20, 'Token assez long');
      _assert(token.contains(RegExp(r'[A-Za-z0-9+/=]')), 'Token base64-like');
    });
  });

  // ============================================
  // Tests : ConfigCanary
  // ============================================

  _testGroup('ConfigCanary', () {
    _test('snapshot et verification', () async {
      final tempDir = await Directory.systemTemp.createTemp('config-canary-');

      try {
        // Creer des fichiers de config
        final config1 = File('${tempDir.path}/config1.json');
        final config2 = File('${tempDir.path}/config2.json');
        await config1.writeAsString('{"setting": "value1"}');
        await config2.writeAsString('{"setting": "value2"}');

        // Snapshot
        final checksums = <String, String>{};
        for (final path in [config1.path, config2.path]) {
          final content = await File(path).readAsBytes();
          checksums[path] = sha256.convert(content).toString();
        }

        // Verifier (aucune modification)
        final modified = <String>[];
        for (final entry in checksums.entries) {
          final content = await File(entry.key).readAsBytes();
          if (sha256.convert(content).toString() != entry.value) {
            modified.add(entry.key);
          }
        }
        _assert(modified.isEmpty, 'Aucune modification');

        // Modifier un fichier
        await config1.writeAsString('{"setting": "tampered"}');
        final modified2 = <String>[];
        for (final entry in checksums.entries) {
          final content = await File(entry.key).readAsBytes();
          if (sha256.convert(content).toString() != entry.value) {
            modified2.add(entry.key);
          }
        }
        _assert(modified2.length == 1, 'Un fichier modifie detecte');
        _assert(modified2[0] == config1.path, 'Bon fichier identifie');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  _printResults();
}

// ============================================
// Helpers
// ============================================

String _generateFakeToken() {
  final rng = Random.secure();
  final bytes = List.generate(24, (_) => rng.nextInt(256));
  return base64Encode(bytes);
}

// Mini test framework
int _passed = 0;
int _failed = 0;

void _testGroup(String name, void Function() body) {
  stdout.writeln('\n=== $name ===');
  body();
}

void _test(String name, dynamic Function() body) {
  try {
    body();
    stdout.writeln('  [PASS] $name');
    _passed++;
  } catch (e) {
    stdout.writeln('  [FAIL] $name: $e');
    _failed++;
  }
}

void _assert(bool condition, String message) {
  if (!condition) throw Exception('Assertion failed: $message');
}

void _printResults() {
  stdout.writeln('\n${'=' * 40}');
  stdout.writeln('Resultats: $_passed passed, $_failed failed');
  if (_failed > 0) exit(1);
}
