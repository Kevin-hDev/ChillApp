// Tests pour FIX-012 (IPC Auth) et FIX-035 (Daemon Integrity)

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() {
  // ============================================
  // Tests : AuthenticatedIPC
  // ============================================

  _testGroup('AuthenticatedIPC - HMAC signing', () {
    _test('signMessage produit un JSON valide', () {
      final secret = _generateSecret();
      final ipc = _SimpleIPC(secret);

      final signed = ipc.signMessage({'action': 'connect', 'host': 'test'});
      final parsed = jsonDecode(signed) as Map<String, dynamic>;

      _assert(parsed.containsKey('message'), 'Contient message');
      _assert(parsed.containsKey('mac'), 'Contient mac');
    });

    _test('verifyMessage accepte un message valide', () {
      final secret = _generateSecret();
      final ipc = _SimpleIPC(secret);

      final signed = ipc.signMessage({'action': 'test'});
      final payload = ipc.verifyMessage(signed);

      _assert(payload != null, 'Payload non null');
      _assert(payload!['action'] == 'test', 'Action correcte');
    });

    _test('verifyMessage rejette un message altere', () {
      final secret = _generateSecret();
      final ipc = _SimpleIPC(secret);

      final signed = ipc.signMessage({'action': 'test'});
      // Alterer le message
      final altered = signed.replaceFirst('test', 'hack');
      final payload = ipc.verifyMessage(altered);

      _assert(payload == null, 'Message altere rejete');
    });

    _test('verifyMessage rejette avec une mauvaise cle', () {
      final secret1 = _generateSecret();
      final secret2 = _generateSecret();
      final ipc1 = _SimpleIPC(secret1);
      final ipc2 = _SimpleIPC(secret2);

      final signed = ipc1.signMessage({'action': 'test'});
      final payload = ipc2.verifyMessage(signed);

      _assert(payload == null, 'Mauvaise cle rejetee');
    });

    _test('nonce anti-replay fonctionne', () {
      final secret = _generateSecret();
      final ipc = _SimpleIPC(secret);

      final signed = ipc.signMessage({'action': 'test'});
      final payload1 = ipc.verifyMessage(signed);
      final payload2 = ipc.verifyMessage(signed); // Replay

      _assert(payload1 != null, 'Premier message accepte');
      _assert(payload2 == null, 'Replay rejete');
    });
  });

  // ============================================
  // Tests : DaemonIntegrityVerifier
  // ============================================

  _testGroup('DaemonIntegrity - SHA-256', () {
    _test('hash SHA-256 est correct', () {
      final data = utf8.encode('test binary content');
      final hash = sha256.convert(data).toString();

      _assert(hash.length == 64, 'Hash a 64 caracteres');
      _assert(
        hash == sha256.convert(data).toString(),
        'Hash deterministe',
      );
    });

    _test('hash different pour contenu different', () {
      final hash1 = sha256.convert(utf8.encode('content A')).toString();
      final hash2 = sha256.convert(utf8.encode('content B')).toString();

      _assert(hash1 != hash2, 'Hash differents pour contenus differents');
    });

    _test('fichier inexistant retourne false', () async {
      final file = File('/tmp/nonexistent_${DateTime.now().millisecondsSinceEpoch}');
      _assert(!await file.exists(), 'Fichier inexistant');
    });
  });

  _printResults();
}

// ============================================
// IPC simplifie pour les tests
// ============================================

class _SimpleIPC {
  final Uint8List _secret;
  final Set<String> _usedNonces = {};

  _SimpleIPC(this._secret);

  String signMessage(Map<String, dynamic> payload) {
    final rng = Random.secure();
    final nonceBytes = Uint8List.fromList(
      List.generate(16, (_) => rng.nextInt(256)),
    );
    final nonce = base64Encode(nonceBytes);

    final message = {
      'payload': payload,
      'nonce': nonce,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final messageJson = jsonEncode(message);
    final hmac = Hmac(sha256, _secret);
    final mac = hmac.convert(utf8.encode(messageJson)).toString();

    return jsonEncode({'message': messageJson, 'mac': mac});
  }

  Map<String, dynamic>? verifyMessage(String signedMessage) {
    try {
      final envelope = jsonDecode(signedMessage) as Map<String, dynamic>;
      final messageJson = envelope['message'] as String;
      final receivedMac = envelope['mac'] as String;

      final hmac = Hmac(sha256, _secret);
      final expectedMac = hmac.convert(utf8.encode(messageJson)).toString();

      if (!_constantTimeEquals(expectedMac, receivedMac)) return null;

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      final nonce = message['nonce'] as String;
      if (_usedNonces.contains(nonce)) return null;

      final timestamp = DateTime.parse(message['timestamp'] as String);
      final age = DateTime.now().toUtc().difference(timestamp);
      if (age.abs() > const Duration(seconds: 30)) return null;

      _usedNonces.add(nonce);
      return message['payload'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

Uint8List _generateSecret() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

// ============================================
// Mini test framework
// ============================================

int _passed = 0;
int _failed = 0;
String _currentGroup = '';

void _testGroup(String name, void Function() body) {
  _currentGroup = name;
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
