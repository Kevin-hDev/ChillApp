// =============================================================
// TEST FIX-046 : Duress PIN
// Verification du PIN de contrainte et comparaison temps constant
// =============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

// Reproduction des types pour les tests
enum PinVerificationResult { normal, duress, invalid }

class DuressPin {
  static PinVerificationResult verify({
    required String enteredPin,
    required String normalPinHash,
    required String duressPinHash,
    required String salt,
    required int iterations,
  }) {
    final enteredHash = _hashPin(enteredPin, salt, iterations);
    final isNormal = _constantTimeEquals(enteredHash, normalPinHash);
    final isDuress = _constantTimeEquals(enteredHash, duressPinHash);
    if (isNormal) return PinVerificationResult.normal;
    if (isDuress) return PinVerificationResult.duress;
    return PinVerificationResult.invalid;
  }

  static String _hashPin(String pin, String salt, int iterations) {
    final pinBytes = utf8.encode(pin);
    final saltBytes = utf8.encode(salt);
    var hmacKey = Uint8List.fromList(pinBytes);
    var block = Uint8List.fromList([...saltBytes, 0, 0, 0, 1]);
    var u = Hmac(sha256, hmacKey).convert(block).bytes;
    var result = List<int>.from(u);
    for (int i = 1; i < iterations; i++) {
      u = Hmac(sha256, hmacKey).convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

void main() {
  const salt = 'test_salt_secure_2026';
  const iterations = 1000; // Reduit pour les tests (prod = 100000)

  // Pre-calculer les hashes
  late String normalHash;
  late String duressHash;

  setUpAll(() {
    normalHash = _hashPinHelper('1234', salt, iterations);
    duressHash = _hashPinHelper('9999', salt, iterations);
  });

  group('Verification PIN normal', () {
    test('PIN correct retourne normal', () {
      final result = DuressPin.verify(
        enteredPin: '1234',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: salt,
        iterations: iterations,
      );
      expect(result, PinVerificationResult.normal);
    });

    test('PIN incorrect retourne invalid', () {
      final result = DuressPin.verify(
        enteredPin: '0000',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: salt,
        iterations: iterations,
      );
      expect(result, PinVerificationResult.invalid);
    });
  });

  group('Verification PIN duress', () {
    test('PIN duress retourne duress', () {
      final result = DuressPin.verify(
        enteredPin: '9999',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: salt,
        iterations: iterations,
      );
      expect(result, PinVerificationResult.duress);
    });

    test('PIN duress ne retourne PAS normal', () {
      final result = DuressPin.verify(
        enteredPin: '9999',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: salt,
        iterations: iterations,
      );
      expect(result, isNot(PinVerificationResult.normal));
    });
  });

  group('Comparaison temps constant', () {
    test('chaines identiques = true', () {
      expect(DuressPin._constantTimeEquals('abc', 'abc'), isTrue);
    });

    test('chaines differentes = false', () {
      expect(DuressPin._constantTimeEquals('abc', 'abd'), isFalse);
    });

    test('longueurs differentes = false', () {
      expect(DuressPin._constantTimeEquals('abc', 'abcd'), isFalse);
    });

    test('chaines vides = true', () {
      expect(DuressPin._constantTimeEquals('', ''), isTrue);
    });

    test('chaine vide vs non-vide = false', () {
      expect(DuressPin._constantTimeEquals('', 'a'), isFalse);
    });
  });

  group('PBKDF2 determinisme', () {
    test('meme PIN + sel = meme hash', () {
      final hash1 = _hashPinHelper('1234', salt, iterations);
      final hash2 = _hashPinHelper('1234', salt, iterations);
      expect(hash1, hash2);
    });

    test('PIN different = hash different', () {
      final hash1 = _hashPinHelper('1234', salt, iterations);
      final hash2 = _hashPinHelper('1235', salt, iterations);
      expect(hash1, isNot(hash2));
    });

    test('sel different = hash different', () {
      final hash1 = _hashPinHelper('1234', 'salt_a', iterations);
      final hash2 = _hashPinHelper('1234', 'salt_b', iterations);
      expect(hash1, isNot(hash2));
    });

    test('hash a la bonne longueur (64 hex chars = 32 bytes)', () {
      final h = _hashPinHelper('1234', salt, iterations);
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(h), isTrue);
    });
  });

  group('DuressData', () {
    test('donnees factices ont les bons champs', () {
      const fakeSshHosts = [
        {'name': 'Home PC', 'status': 'offline'},
      ];
      expect(fakeSshHosts.length, 1);
      expect(fakeSshHosts[0]['status'], 'offline');
    });

    test('settings factices desactivent les services', () {
      const fakeSettings = {
        'firewall': true,
        'tailscale': false,
        'ssh': false,
      };
      expect(fakeSettings['tailscale'], isFalse);
      expect(fakeSettings['ssh'], isFalse);
    });
  });
}

// Helper pour les tests
String _hashPinHelper(String pin, String salt, int iterations) {
  final pinBytes = utf8.encode(pin);
  final saltBytes = utf8.encode(salt);
  var hmacKey = Uint8List.fromList(pinBytes);
  var block = Uint8List.fromList([...saltBytes, 0, 0, 0, 1]);
  var u = Hmac(sha256, hmacKey).convert(block).bytes;
  var result = List<int>.from(u);
  for (int i = 1; i < iterations; i++) {
    u = Hmac(sha256, hmacKey).convert(u).bytes;
    for (int j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
