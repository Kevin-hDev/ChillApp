// Test pour FIX-001 : Nettoyage securise de la memoire
import 'dart:typed_data';
import 'package:test/test.dart';

// Import relatif au fichier fix
// En integration reelle : import 'package:chill_app/core/security/secure_memory.dart';
import 'fix_001_secure_memory.dart';

void main() {
  group('SecureBytes', () {
    test('stocke et retourne les donnees correctement', () {
      final secret = SecureBytes.fromString('12345678');
      expect(secret.bytes, isNotEmpty);
      expect(secret.length, equals(8));
      secret.dispose();
    });

    test('dispose zerorise la memoire', () {
      final secret = SecureBytes.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final bytesRef = secret.bytes; // Reference au meme Uint8List
      secret.dispose();
      // Apres dispose, le contenu doit etre tout a zero
      expect(bytesRef.every((b) => b == 0), isTrue);
    });

    test('acces apres dispose leve une exception', () {
      final secret = SecureBytes.fromString('test');
      secret.dispose();
      expect(() => secret.bytes, throwsStateError);
    });

    test('double dispose est sans effet', () {
      final secret = SecureBytes.fromString('test');
      secret.dispose();
      secret.dispose(); // Pas d'exception
      expect(secret.isDisposed, isTrue);
    });
  });

  group('SecureUint8ListExtension', () {
    test('secureZero met a zero tout le contenu', () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      data.secureZero();
      expect(data.every((b) => b == 0), isTrue);
    });
  });

  group('constantTimeEquals', () {
    test('retourne true pour des listes identiques', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('retourne false pour des listes differentes', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('retourne false pour des longueurs differentes', () {
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('retourne true pour des listes vides', () {
      expect(constantTimeEquals([], []), isTrue);
    });

    test('fonctionne avec Uint8List', () {
      final a = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      final b = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      expect(constantTimeEquals(a, b), isTrue);
    });
  });
}
