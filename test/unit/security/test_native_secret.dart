import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/native_secret.dart';

void main() {
  group('NativeSecret — allocation et proprietes de base', () {
    test('1. allocate cree un secret avec la bonne longueur', () {
      final secret = NativeSecret.allocate(32);
      try {
        expect(secret.length, equals(32));
        expect(secret.isDisposed, isFalse);
      } finally {
        secret.dispose();
      }
    });

    test('2. fromBytes copie correctement les octets', () {
      final source = Uint8List.fromList([1, 2, 3, 4, 5]);
      final secret = NativeSecret.fromBytes(source);
      try {
        final result = secret.bytes;
        expect(result, equals([1, 2, 3, 4, 5]));
      } finally {
        secret.dispose();
      }
    });

    test('3. fromBytes efface les octets source apres copie', () {
      final source = Uint8List.fromList([10, 20, 30, 40]);
      // fromBytes modifie la source en place
      NativeSecret.fromBytes(source).dispose();
      // La source doit etre remplie de zeros
      expect(source, equals([0, 0, 0, 0]));
    });
  });

  group('NativeSecret — lecture et ecriture', () {
    test('4. bytes retourne le contenu correct', () {
      final secret = NativeSecret.allocate(4);
      try {
        secret.write(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));
        final result = secret.bytes;
        expect(result[0], equals(0xDE));
        expect(result[1], equals(0xAD));
        expect(result[2], equals(0xBE));
        expect(result[3], equals(0xEF));
      } finally {
        secret.dispose();
      }
    });

    test('5. write met a jour le contenu correctement', () {
      final secret = NativeSecret.allocate(8);
      try {
        secret.write(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
        expect(secret.bytes, equals([1, 2, 3, 4, 5, 6, 7, 8]));
        // Ecrase avec de nouvelles valeurs
        secret.write(Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]));
        expect(secret.bytes, equals([9, 9, 9, 9, 9, 9, 9, 9]));
      } finally {
        secret.dispose();
      }
    });

    test('6. write avec offset ecrit aux bons emplacements', () {
      final secret = NativeSecret.allocate(8);
      try {
        // Initialise tout a zero
        secret.write(Uint8List(8));
        // Ecrit 3 octets a partir du decalage 2
        secret.write(Uint8List.fromList([0xAA, 0xBB, 0xCC]), offset: 2);
        final result = secret.bytes;
        expect(result[0], equals(0));
        expect(result[1], equals(0));
        expect(result[2], equals(0xAA));
        expect(result[3], equals(0xBB));
        expect(result[4], equals(0xCC));
        expect(result[5], equals(0));
      } finally {
        secret.dispose();
      }
    });

    test('7. write au-dela de la longueur leve une RangeError', () {
      final secret = NativeSecret.allocate(4);
      try {
        expect(
          () => secret.write(Uint8List.fromList([1, 2, 3, 4, 5])),
          throwsRangeError,
        );
      } finally {
        secret.dispose();
      }
    });
  });

  group('NativeSecret — cycle de vie et securite', () {
    test('8. dispose marque le secret comme libere', () {
      final secret = NativeSecret.allocate(16);
      expect(secret.isDisposed, isFalse);
      secret.dispose();
      expect(secret.isDisposed, isTrue);
    });

    test('9. acceder a bytes apres dispose leve une StateError', () {
      final secret = NativeSecret.allocate(8);
      secret.dispose();
      expect(
        () => secret.bytes,
        throwsA(isA<StateError>()),
      );
    });

    test('10. double dispose ne provoque pas de crash', () {
      final secret = NativeSecret.allocate(8);
      secret.dispose();
      // Le second dispose ne doit pas lancer d exception
      expect(() => secret.dispose(), returnsNormally);
      expect(secret.isDisposed, isTrue);
    });

    test('11. la memoire allouee est initialement a zero (calloc)', () {
      final secret = NativeSecret.allocate(64);
      try {
        final data = secret.bytes;
        // calloc garantit que tous les octets sont a zero a l initialisation
        for (int i = 0; i < data.length; i++) {
          expect(data[i], equals(0),
              reason: 'Octet $i devrait etre zero apres calloc');
        }
      } finally {
        secret.dispose();
      }
    });
  });
}
