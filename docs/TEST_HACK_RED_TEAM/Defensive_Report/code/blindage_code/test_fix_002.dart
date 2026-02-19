// Test pour FIX-002 : Error handling securise
import 'package:test/test.dart';

// En integration reelle : import 'package:chill_app/core/security/secure_error_handler.dart';
import 'fix_002_secure_error_handling.dart';

void main() {
  group('SecureErrorHandler.sanitizeForUser', () {
    test('supprime les chemins Unix', () {
      final result = SecureErrorHandler.sanitizeForUser(
        'Erreur: fichier /home/user/.ssh/id_rsa non trouve',
      );
      expect(result.contains('/home'), isFalse);
      expect(result.contains('[chemin]'), isTrue);
    });

    test('supprime les chemins Windows', () {
      final result = SecureErrorHandler.sanitizeForUser(
        'Erreur: C:\\Users\\admin\\secrets.txt non trouve',
      );
      expect(result.contains('C:\\'), isFalse);
      expect(result.contains('[chemin]'), isTrue);
    });

    test('supprime les adresses IP', () {
      final result = SecureErrorHandler.sanitizeForUser(
        'Connexion refusee vers 192.168.1.100:22',
      );
      expect(result.contains('192.168'), isFalse);
      expect(result.contains('[adresse]'), isTrue);
    });

    test('supprime les tokens longs', () {
      final token = 'A' * 30; // Token de 30 caracteres
      final result = SecureErrorHandler.sanitizeForUser(
        'Token invalide: $token',
      );
      expect(result.contains(token), isFalse);
      expect(result.contains('[masque]'), isTrue);
    });

    test('preserve les messages courts normaux', () {
      final result = SecureErrorHandler.sanitizeForUser(
        'Erreur de connexion',
      );
      expect(result, equals('Erreur de connexion'));
    });
  });
}
