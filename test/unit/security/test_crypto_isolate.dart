import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/crypto_isolate.dart';

// =============================================================
// Tests : CryptoIsolate (FIX-003)
// =============================================================

/// Calcul PBKDF2 synchrone de référence pour valider la cohérence.
String _referencePbkdf2(String pin, String salt,
    {int iterations = 100000, int keyLength = 32}) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  final saltBytes = utf8.encode(salt);
  var result = <int>[];
  var blockIndex = 1;

  while (result.length < keyLength) {
    final blockBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, blockIndex);
    var u = hmac.convert([...saltBytes, ...blockBytes]).bytes;
    var block = List<int>.from(u);

    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < block.length; j++) {
        block[j] ^= u[j];
      }
    }
    result.addAll(block);
    blockIndex++;
  }

  return base64Encode(Uint8List.fromList(result.sublist(0, keyLength)));
}

void main() {
  group('CryptoIsolate.hashPinIsolated', () {
    // Test 1 : le résultat est une chaîne base64 de 44 caractères
    test('retourne une chaîne base64 de 44 caractères', () async {
      final hash = await CryptoIsolate.hashPinIsolated('12345678', 'sel_test');
      expect(hash.length, equals(44));
      // Vérifie que c'est du base64 valide (pas d'exception)
      expect(() => base64Decode(hash), returnsNormally);
    });

    // Test 2 : même pin + salt → même hash (déterministe)
    test('même pin et salt → hash identique (déterministe)', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('87654321', 'sel_stable');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('87654321', 'sel_stable');
      expect(hash1, equals(hash2));
    });

    // Test 3 : PIN différent → hash différent
    test('PIN différent → hash différent', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('11111111', 'meme_sel');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('22222222', 'meme_sel');
      expect(hash1, isNot(equals(hash2)));
    });

    // Test 4 : salt différent → hash différent
    test('salt différent → hash différent', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('12345678', 'sel_alpha');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('12345678', 'sel_beta');
      expect(hash1, isNot(equals(hash2)));
    });

    // Test 5 : cohérence avec le calcul PBKDF2 synchrone de référence
    // Note : ce test prend ~2-3s (100 000 itérations × 2)
    test('cohérence avec le calcul PBKDF2 synchrone de référence', () async {
      const pin = '99887766';
      const salt = 'sel_reference';
      final isolateHash =
          await CryptoIsolate.hashPinIsolated(pin, salt);
      final referenceHash = _referencePbkdf2(pin, salt);
      expect(isolateHash, equals(referenceHash));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
