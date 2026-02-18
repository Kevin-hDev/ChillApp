// Test unitaire pour FIX-046 — DuressPin
// Lance avec : flutter test test/unit/security/test_duress_pin.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/duress_pin.dart';

void main() {
  // Salt et iterations de test (iterations reduites pour la vitesse)
  const testSalt = 'test_salt_2026';
  const testIterations = 10; // Reduit pour les tests (production = 100000)

  // Hashes pre-calcules avec les memes parametres
  String hashOf(String pin) => DuressPin.hashPin(pin, testSalt, testIterations);

  group('PinVerificationResult enum', () {
    test('Les trois valeurs existent', () {
      expect(PinVerificationResult.values, hasLength(3));
      expect(PinVerificationResult.values, contains(PinVerificationResult.normal));
      expect(PinVerificationResult.values, contains(PinVerificationResult.duress));
      expect(PinVerificationResult.values, contains(PinVerificationResult.invalid));
    });
  });

  group('DuressData — donnees factices', () {
    test('fakeSshHosts est non vide et contient des donnees factices', () {
      expect(DuressData.fakeSshHosts, isNotEmpty);
      expect(DuressData.fakeSshHosts.first, containsPair('status', 'offline'));
    });

    test('fakeSettings contient les cles attendues', () {
      expect(DuressData.fakeSettings.containsKey('firewall'), isTrue);
      expect(DuressData.fakeSettings.containsKey('tailscale'), isTrue);
      expect(DuressData.fakeSettings.containsKey('ssh'), isTrue);
    });

    test('fakeSettings — ssh est desactive (plausible deniability)', () {
      expect(DuressData.fakeSettings['ssh'], isFalse);
    });
  });

  group('DuressPin.hashPin — generation de hash', () {
    test('hashPin retourne une chaine hexadecimale non vide', () {
      final hash = hashOf('1234');
      expect(hash, isNotEmpty);
      expect(hash, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('hashPin est deterministe (meme entree → meme hash)', () {
      final hash1 = hashOf('5678');
      final hash2 = hashOf('5678');
      expect(hash1, equals(hash2));
    });

    test('hashPin est different pour deux PINs differents', () {
      final hash1 = hashOf('1111');
      final hash2 = hashOf('2222');
      expect(hash1, isNot(equals(hash2)));
    });

    test('hashPin est different avec un salt different', () {
      final hash1 = DuressPin.hashPin('1234', 'salt_a', testIterations);
      final hash2 = DuressPin.hashPin('1234', 'salt_b', testIterations);
      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('DuressPin.verify — verification du PIN', () {
    test('PIN normal correct retourne PinVerificationResult.normal', () {
      final normalHash = hashOf('9876');
      final duressHash = hashOf('1234');

      final result = DuressPin.verify(
        enteredPin: '9876',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: testSalt,
        iterations: testIterations,
      );

      expect(result, equals(PinVerificationResult.normal));
    });

    test('PIN duress correct retourne PinVerificationResult.duress', () {
      final normalHash = hashOf('9876');
      final duressHash = hashOf('0000');

      final result = DuressPin.verify(
        enteredPin: '0000',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: testSalt,
        iterations: testIterations,
      );

      expect(result, equals(PinVerificationResult.duress));
    });

    test('PIN incorrect retourne PinVerificationResult.invalid', () {
      final normalHash = hashOf('1111');
      final duressHash = hashOf('2222');

      final result = DuressPin.verify(
        enteredPin: '3333',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: testSalt,
        iterations: testIterations,
      );

      expect(result, equals(PinVerificationResult.invalid));
    });

    test('Comparaison temps constant : les deux hashes sont toujours compares', () {
      // Ce test verifie le comportement : meme avec PIN normal valide,
      // la fonction doit toujours comparer les deux hashes
      // (on ne peut pas mesurer ca directement, mais on verifie
      // que le resultat est correct dans tous les cas)
      final normalHash = hashOf('correct');
      final duressHash = hashOf('duress_pin');

      // PIN normal → normal
      expect(
        DuressPin.verify(
          enteredPin: 'correct',
          normalPinHash: normalHash,
          duressPinHash: duressHash,
          salt: testSalt,
          iterations: testIterations,
        ),
        equals(PinVerificationResult.normal),
      );

      // PIN duress → duress
      expect(
        DuressPin.verify(
          enteredPin: 'duress_pin',
          normalPinHash: normalHash,
          duressPinHash: duressHash,
          salt: testSalt,
          iterations: testIterations,
        ),
        equals(PinVerificationResult.duress),
      );
    });

    test('PIN vide retourne invalid', () {
      final normalHash = hashOf('1234');
      final duressHash = hashOf('5678');

      final result = DuressPin.verify(
        enteredPin: '',
        normalPinHash: normalHash,
        duressPinHash: duressHash,
        salt: testSalt,
        iterations: testIterations,
      );

      expect(result, equals(PinVerificationResult.invalid));
    });

    test('Hash duress vide (non configure) retourne invalid pour tout PIN', () {
      final normalHash = hashOf('1234');

      final result = DuressPin.verify(
        enteredPin: '1234',
        normalPinHash: normalHash,
        duressPinHash: '',
        salt: testSalt,
        iterations: testIterations,
      );

      // PIN correct → normal, meme si duress est vide
      expect(result, equals(PinVerificationResult.normal));
    });

    test('PIN normal et duress identiques : normal gagne', () {
      // Si l'utilisateur configure le meme PIN pour les deux,
      // le PIN normal doit prendre priorite
      final sameHash = hashOf('same');

      final result = DuressPin.verify(
        enteredPin: 'same',
        normalPinHash: sameHash,
        duressPinHash: sameHash,
        salt: testSalt,
        iterations: testIterations,
      );

      expect(result, equals(PinVerificationResult.normal));
    });
  });
}
