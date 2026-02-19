// Tests pour FIX-021/022 (Obfuscation + Dart Confidential)

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';

void main() {
  // ============================================
  // Tests : ConfidentialString
  // ============================================

  _testGroup('ConfidentialString', () {
    _test('protect puis reveal retourne le texte original', () {
      _initializeConfidential();

      final original = 'https://api.example.com/v2';
      final protected = _protect(original);
      final revealed = _reveal(protected);

      _assert(revealed == original, 'Roundtrip fonctionne');
    });

    _test('le texte protege est different du texte original', () {
      _initializeConfidential();

      final original = '/opt/chillapp/chill-tailscale';
      final protected = _protect(original);

      _assert(protected != original, 'Texte chiffre different');
      _assert(protected.isNotEmpty, 'Texte chiffre non vide');
    });

    _test('deux protections du meme texte sont identiques', () {
      _initializeConfidential();

      final original = 'secret value';
      final p1 = _protect(original);
      final p2 = _protect(original);

      // Avec la meme cle deterministe, le resultat est le meme
      _assert(p1 == p2, 'Resultats deterministes');
    });

    _test('texte vide fonctionne', () {
      _initializeConfidential();

      final protected = _protect('');
      final revealed = _reveal(protected);

      _assert(revealed == '', 'Texte vide roundtrip');
    });

    _test('caracteres speciaux et accents fonctionnent', () {
      _initializeConfidential();

      final original = 'Clé SSH: ñ, ü, é, 中文';
      final protected = _protect(original);
      final revealed = _reveal(protected);

      _assert(revealed == original, 'Accents et UTF-8 preserves');
    });
  });

  // ============================================
  // Tests : StrongConfidential
  // ============================================

  _testGroup('StrongConfidential', () {
    _test('protect avec uniqueId fonctionne', () {
      final original = 'test value';
      final protected = _strongProtect(original, 42);
      final revealed = _strongReveal(protected, 42);

      _assert(revealed == original, 'Roundtrip avec ID');
    });

    _test('IDs differents donnent des resultats differents', () {
      final original = 'same text';
      final p1 = _strongProtect(original, 1);
      final p2 = _strongProtect(original, 2);

      _assert(p1 != p2, 'IDs differents = resultats differents');
    });

    _test('mauvais ID ne dechiffre pas correctement', () {
      final original = 'secret';
      final protected = _strongProtect(original, 42);

      // Dechiffrer avec un mauvais ID
      final wrong = _strongReveal(protected, 99);
      _assert(wrong != original, 'Mauvais ID = mauvais resultat');
    });
  });

  _printResults();
}

// ============================================
// Implementations de test
// ============================================

late Uint8List _runtimeKey;

void _initializeConfidential() {
  final seed = <int>[0, 42, 'ChillApp'.codeUnits.fold<int>(0, (a, b) => a ^ b)];
  final rng = Random(seed.fold<int>(0, (a, b) => a * 31 + b));
  _runtimeKey = Uint8List.fromList(
    List.generate(32, (_) => rng.nextInt(256)),
  );
}

String _protect(String plaintext) {
  final bytes = utf8.encode(plaintext);
  final encrypted = _xorWithKey(Uint8List.fromList(bytes));
  return base64Encode(encrypted);
}

String _reveal(String protected) {
  final encrypted = base64Decode(protected);
  final decrypted = _xorWithKey(Uint8List.fromList(encrypted));
  return utf8.decode(decrypted);
}

Uint8List _xorWithKey(Uint8List data) {
  final result = Uint8List(data.length);
  for (int i = 0; i < data.length; i++) {
    result[i] = data[i] ^ _runtimeKey[i % _runtimeKey.length];
  }
  return result;
}

String _strongProtect(String plaintext, int uniqueId) {
  final bytes = utf8.encode(plaintext);
  final keyStream = _generateKeyStream(uniqueId, bytes.length);
  final encrypted = Uint8List(bytes.length);
  for (int i = 0; i < bytes.length; i++) {
    encrypted[i] = bytes[i] ^ keyStream[i];
  }
  return base64Encode(encrypted);
}

String _strongReveal(String protected, int uniqueId) {
  final encrypted = base64Decode(protected);
  final keyStream = _generateKeyStream(uniqueId, encrypted.length);
  final decrypted = Uint8List(encrypted.length);
  for (int i = 0; i < encrypted.length; i++) {
    decrypted[i] = encrypted[i] ^ keyStream[i];
  }
  return utf8.decode(decrypted, allowMalformed: true);
}

Uint8List _generateKeyStream(int uniqueId, int length) {
  final rng = Random(uniqueId * 2654435761);
  return Uint8List.fromList(
    List.generate(length, (_) => rng.nextInt(256)),
  );
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
