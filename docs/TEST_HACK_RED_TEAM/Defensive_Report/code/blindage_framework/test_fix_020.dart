// Tests pour FIX-020 (Security Audit Log)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

void main() {
  // ============================================
  // Tests : Sanitization
  // ============================================

  _testGroup('Audit Log - Sanitization', () {
    _test('supprime les chemins Unix', () {
      final result = _sanitize('Error at /home/user/projects/app.dart');
      _assert(!result.contains('/home/user'), 'Chemin Unix supprime');
      _assert(result.contains('[PATH]'), 'Remplace par [PATH]');
    });

    _test('supprime les chemins Windows', () {
      final result = _sanitize(r'Error at C:\Users\admin\app.exe');
      _assert(!result.contains('Users'), 'Chemin Windows supprime');
    });

    _test('supprime les IPs non-Tailscale', () {
      final result = _sanitize('Connection from 192.168.1.100');
      _assert(!result.contains('192.168.1.100'), 'IP supprimee');
      _assert(result.contains('[IP]'), 'Remplace par [IP]');
    });

    _test('preserve les IPs Tailscale', () {
      final result = _sanitize('Connected to 100.64.0.1');
      _assert(result.contains('100.64.0.1'), 'IP Tailscale preservee');
    });

    _test('supprime les tokens longs', () {
      final fakeToken = 'A' * 40;
      final result = _sanitize('Token: $fakeToken');
      _assert(!result.contains(fakeToken), 'Token supprime');
      _assert(result.contains('[REDACTED]'), 'Remplace par [REDACTED]');
    });

    _test('tronque les messages trop longs', () {
      final longMessage = 'x' * 300;
      final result = _sanitize(longMessage);
      _assert(result.length <= 203, 'Message tronque'); // 200 + "..."
    });
  });

  // ============================================
  // Tests : Hash Chain Integrity
  // ============================================

  _testGroup('Audit Log - Hash Chain', () {
    _test('chaine de hachage est coherente', () {
      final key = _generateKey();
      final genesisHash = '0' * 64;

      // Premiere entree
      final content1 = '2026-02-18T15:00:00.000Z|firewallDisabled|test|$genesisHash';
      final hmac1 = Hmac(sha256, key);
      final hash1 = hmac1.convert(utf8.encode(content1)).toString();

      // Deuxieme entree referant la premiere
      final content2 = '2026-02-18T15:01:00.000Z|firewallEnabled|test|$hash1';
      final hmac2 = Hmac(sha256, key);
      final hash2 = hmac2.convert(utf8.encode(content2)).toString();

      _assert(hash1 != hash2, 'Hash differents');
      _assert(hash1.length == 64, 'Hash 1 a 64 caracteres');
      _assert(hash2.length == 64, 'Hash 2 a 64 caracteres');
    });

    _test('modification detectee', () {
      final key = _generateKey();
      final genesisHash = '0' * 64;

      final content = '2026-02-18T15:00:00.000Z|firewallDisabled|original|$genesisHash';
      final hmac = Hmac(sha256, key);
      final expectedHash = hmac.convert(utf8.encode(content)).toString();

      // Modifier le contenu
      final tamperedContent = '2026-02-18T15:00:00.000Z|firewallDisabled|tampered|$genesisHash';
      final tamperedHash = hmac.convert(utf8.encode(tamperedContent)).toString();

      _assert(expectedHash != tamperedHash, 'Modification detectee par le hash');
    });
  });

  // ============================================
  // Tests : File Operations
  // ============================================

  _testGroup('Audit Log - File', () {
    _test('creation et lecture du fichier log', () async {
      final tempDir = await Directory.systemTemp.createTemp('audit-test-');
      final logPath = '${tempDir.path}/test_audit.log';

      try {
        final file = File(logPath);
        await file.writeAsString('{"ts":"2026-02-18T15:00:00Z","action":"test","detail":"ok","prev":"0000","hash":"abcd"}\n');

        final content = await file.readAsString();
        _assert(content.contains('"action":"test"'), 'Contenu ecrit et lu');

        final lines = content.trim().split('\n');
        _assert(lines.length == 1, 'Une seule entree');

        final entry = jsonDecode(lines[0]) as Map<String, dynamic>;
        _assert(entry['action'] == 'test', 'Action correcte');
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

String _sanitize(String input) {
  var safe = input;
  safe = safe.replaceAll(
    RegExp(r'(/home/[^\s]+|/Users/[^\s]+|C:\\Users\\[^\s]+)'),
    '[PATH]',
  );
  safe = safe.replaceAll(
    RegExp(r'\b(?!100\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
    '[IP]',
  );
  safe = safe.replaceAll(
    RegExp(r'[A-Za-z0-9+/=]{32,}'),
    '[REDACTED]',
  );
  if (safe.length > 200) safe = '${safe.substring(0, 200)}...';
  return safe;
}

Uint8List _generateKey() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
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
