// Test pour FIX-004 : Extension types pour donnees sensibles
import 'dart:typed_data';
import 'package:test/test.dart';

import 'fix_004_sensitive_types.dart';

void main() {
  group('PinBytes', () {
    test('fromString convertit correctement', () {
      final pin = PinBytes.fromString('12345678');
      expect(pin.length, equals(8));
      expect(pin.rawBytes[0], equals('1'.codeUnitAt(0)));
    });

    test('secureDispose zerorise les bytes', () {
      final pin = PinBytes.fromString('12345678');
      final ref = pin.rawBytes;
      pin.secureDispose();
      expect(ref.every((b) => b == 0), isTrue);
    });
  });

  group('SaltData', () {
    test('stocke et retourne la valeur', () {
      final salt = SaltData('abc123');
      expect(salt.value, equals('abc123'));
      expect(salt.length, equals(6));
    });
  });

  group('DerivedHash', () {
    test('equalsConstantTime retourne true pour meme hash', () {
      final h1 = DerivedHash('abcdef1234567890');
      final h2 = DerivedHash('abcdef1234567890');
      expect(h1.equalsConstantTime(h2), isTrue);
    });

    test('equalsConstantTime retourne false pour hash different', () {
      final h1 = DerivedHash('abcdef1234567890');
      final h2 = DerivedHash('abcdef1234567891');
      expect(h1.equalsConstantTime(h2), isFalse);
    });

    test('equalsConstantTime retourne false pour longueurs differentes', () {
      final h1 = DerivedHash('short');
      final h2 = DerivedHash('longer_hash');
      expect(h1.equalsConstantTime(h2), isFalse);
    });
  });
}
