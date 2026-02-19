// Test pour FIX-003 : Isolation crypto dans un Isolate
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

// En integration reelle : import 'package:chill_app/core/security/crypto_isolate.dart';
import 'fix_003_crypto_isolate.dart';

void main() {
  group('CryptoIsolate', () {
    test('hashPinIsolated produit un hash base64 de 44 caracteres', () async {
      final hash = await CryptoIsolate.hashPinIsolated('12345678', 'testSalt');
      // PBKDF2 32 bytes = 44 chars en base64
      expect(hash.length, equals(44));
      // Verifier que c'est du base64 valide
      expect(() => base64Decode(hash), returnsNormally);
    });

    test('le meme PIN+salt donne le meme hash', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('12345678', 'sameSalt');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('12345678', 'sameSalt');
      expect(hash1, equals(hash2));
    });

    test('des PIN differents donnent des hash differents', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('12345678', 'salt1');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('87654321', 'salt1');
      expect(hash1, isNot(equals(hash2)));
    });

    test('des sels differents donnent des hash differents', () async {
      final hash1 =
          await CryptoIsolate.hashPinIsolated('12345678', 'saltA');
      final hash2 =
          await CryptoIsolate.hashPinIsolated('12345678', 'saltB');
      expect(hash1, isNot(equals(hash2)));
    });

    test('le resultat est coherent avec une implementation PBKDF2 locale',
        () async {
      const pin = '99887766';
      const salt = 'verifySalt';

      // Calcul local pour verification
      final hmac = Hmac(sha256, utf8.encode(pin));
      final saltBytes = utf8.encode(salt);
      final blockBytes = Uint8List(4)..buffer.asByteData().setUint32(0, 1);
      var u = hmac.convert([...saltBytes, ...blockBytes]).bytes;
      var block = List<int>.from(u);
      for (var i = 1; i < 100000; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < block.length; j++) {
          block[j] ^= u[j];
        }
      }
      final expectedHash =
          base64Encode(Uint8List.fromList(block.sublist(0, 32)));

      // Calcul dans l'isolate
      final isolatedHash =
          await CryptoIsolate.hashPinIsolated(pin, salt);

      expect(isolatedHash, equals(expectedHash));
    });
  });
}
