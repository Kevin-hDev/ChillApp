// Test pour FIX-004 : Extension types pour données sensibles
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/sensitive_types.dart';

void main() {
  group('PinBytes', () {
    test('fromString convertit correctement en bytes', () {
      final pin = PinBytes.fromString('12345678');
      expect(pin.length, equals(8));
      expect(pin.rawBytes[0], equals('1'.codeUnitAt(0)));
    });

    test('isEmpty retourne false pour un PIN non vide', () {
      final pin = PinBytes.fromString('1234');
      expect(pin.isEmpty, isFalse);
    });

    test('isEmpty retourne true pour un PIN vide', () {
      final pin = PinBytes(Uint8List(0));
      expect(pin.isEmpty, isTrue);
    });

    test('secureDispose zéroïse les bytes', () {
      final pin = PinBytes.fromString('12345678');
      final ref = pin.rawBytes;
      pin.secureDispose();
      expect(ref.every((b) => b == 0), isTrue);
    });

    test('rawBytes donne accès aux données brutes', () {
      final pin = PinBytes.fromString('ABCD');
      expect(pin.rawBytes, isA<Uint8List>());
      expect(pin.rawBytes.length, equals(4));
      pin.secureDispose();
    });

    test('fromString avec PIN numérique encode correctement', () {
      final pin = PinBytes.fromString('0');
      expect(pin.rawBytes[0], equals('0'.codeUnitAt(0)));
      pin.secureDispose();
    });

    test('secureDispose deux fois ne lève pas d exception', () {
      final pin = PinBytes.fromString('1234');
      pin.secureDispose();
      // Deuxième dispose : les bytes sont déjà à zéro, mais ne doit pas planter
      expect(() => pin.secureDispose(), returnsNormally);
    });
  });

  group('SaltData', () {
    test('stocke et retourne la valeur', () {
      final salt = SaltData('abc123');
      expect(salt.value, equals('abc123'));
      expect(salt.length, equals(6));
    });

    test('isEmpty retourne true pour une chaîne vide', () {
      final salt = SaltData('');
      expect(salt.isEmpty, isTrue);
    });

    test('isEmpty retourne false pour une valeur non vide', () {
      final salt = SaltData('sel_crypto');
      expect(salt.isEmpty, isFalse);
    });

    test('length correspond au nombre de caractères', () {
      final salt = SaltData('abcdefgh');
      expect(salt.length, equals(8));
    });
  });

  group('DerivedHash', () {
    test('equalsConstantTime retourne true pour même hash', () {
      final h1 = DerivedHash('abcdef1234567890');
      final h2 = DerivedHash('abcdef1234567890');
      expect(h1.equalsConstantTime(h2), isTrue);
    });

    test('equalsConstantTime retourne false pour hash différent', () {
      final h1 = DerivedHash('abcdef1234567890');
      final h2 = DerivedHash('abcdef1234567891');
      expect(h1.equalsConstantTime(h2), isFalse);
    });

    test('equalsConstantTime retourne false pour longueurs différentes', () {
      final h1 = DerivedHash('short');
      final h2 = DerivedHash('longer_hash');
      expect(h1.equalsConstantTime(h2), isFalse);
    });

    test('equalsConstantTime retourne true pour chaînes vides identiques', () {
      final h1 = DerivedHash('');
      final h2 = DerivedHash('');
      expect(h1.equalsConstantTime(h2), isTrue);
    });

    test('value retourne la valeur du hash', () {
      final hash = DerivedHash('deadbeef');
      expect(hash.value, equals('deadbeef'));
    });

    test('length retourne la longueur du hash', () {
      final hash = DerivedHash('12345678');
      expect(hash.length, equals(8));
    });

    test('equalsConstantTime distingue des hashes qui ne diffèrent qu au dernier caractère', () {
      final h1 = DerivedHash('aaaaaaaaaaaaaaaa');
      final h2 = DerivedHash('aaaaaaaaaaaaaaab');
      expect(h1.equalsConstantTime(h2), isFalse);
    });
  });
}
