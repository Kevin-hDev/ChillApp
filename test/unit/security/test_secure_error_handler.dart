// =============================================================
// Tests unitaires — FIX-002 : SecureErrorHandler
// Vérifier que la sanitisation des messages d'erreur fonctionne
// correctement et ne fuite pas d'informations sensibles.
// =============================================================
//
// Exécuter avec :
//   flutter test test/unit/security/test_secure_error_handler.dart
//
// =============================================================

import 'package:test/test.dart';
import 'package:chill_app/core/security/secure_error_handler.dart';

void main() {
  // On teste la méthode interne `sanitize` (toujours active)
  // car `sanitizeForUser` retourne le message brut en mode debug.

  group('SecureErrorHandler.sanitize — chemins Unix', () {
    test('supprime un chemin /home/user complet', () {
      final result = SecureErrorHandler.sanitize(
        'Erreur: fichier /home/user/.ssh/id_rsa non trouvé',
      );
      expect(result.contains('/home'), isFalse,
          reason: 'Le chemin /home doit être masqué');
      expect(result.contains('[chemin]'), isTrue,
          reason: 'Le placeholder [chemin] doit apparaître');
    });

    test('supprime un chemin /etc/passwd', () {
      final result = SecureErrorHandler.sanitize(
        'Permission refusée: /etc/passwd',
      );
      expect(result.contains('/etc'), isFalse);
      expect(result.contains('[chemin]'), isTrue);
    });

    test('supprime un chemin /tmp/secret.key', () {
      final result = SecureErrorHandler.sanitize(
        'Impossible de lire /tmp/secret.key',
      );
      expect(result.contains('/tmp'), isFalse);
      expect(result.contains('[chemin]'), isTrue);
    });
  });

  group('SecureErrorHandler.sanitize — chemins Windows', () {
    test('supprime un chemin C:\\Users\\admin', () {
      final result = SecureErrorHandler.sanitize(
        r'Erreur: C:\Users\admin\secrets.txt non trouvé',
      );
      expect(result.contains(r'C:\'), isFalse,
          reason: 'Le chemin Windows doit être masqué');
      expect(result.contains('[chemin]'), isTrue,
          reason: 'Le placeholder [chemin] doit apparaître');
    });

    test('supprime un chemin D:\\AppData\\config.ini', () {
      final result = SecureErrorHandler.sanitize(
        r'Lecture: D:\AppData\config.ini échouée',
      );
      expect(result.contains(r'D:\'), isFalse);
      expect(result.contains('[chemin]'), isTrue);
    });
  });

  group('SecureErrorHandler.sanitize — adresses IP', () {
    test('supprime une adresse IPv4 simple', () {
      final result = SecureErrorHandler.sanitize(
        'Connexion refusée vers 192.168.1.100',
      );
      expect(result.contains('192.168'), isFalse,
          reason: "L'adresse IP doit être masquée");
      expect(result.contains('[adresse]'), isTrue,
          reason: 'Le placeholder [adresse] doit apparaître');
    });

    test('supprime une adresse IPv4 avec port', () {
      final result = SecureErrorHandler.sanitize(
        'Timeout sur 10.0.0.1:22 après 30s',
      );
      expect(result.contains('10.0.0'), isFalse);
      expect(result.contains('[adresse]'), isTrue);
    });

    test('supprime une adresse de loopback', () {
      final result = SecureErrorHandler.sanitize(
        'Service unavailable at 127.0.0.1:8080',
      );
      expect(result.contains('127.0.0.1'), isFalse);
      expect(result.contains('[adresse]'), isTrue);
    });
  });

  group('SecureErrorHandler.sanitize — tokens et secrets', () {
    test('masque un token de 30 caractères', () {
      final token = 'A' * 30;
      final result = SecureErrorHandler.sanitize('Token invalide: $token');
      expect(result.contains(token), isFalse,
          reason: 'Un token long doit être masqué');
      expect(result.contains('[masque]'), isTrue,
          reason: 'Le placeholder [masque] doit apparaître');
    });

    test('masque une API key de 40 caractères alphanumériques', () {
      const apiKey = 'sk_live_AbCdEfGhIjKlMnOpQrStUvWxYz123456789';
      final result = SecureErrorHandler.sanitize('Auth failed: $apiKey');
      expect(result.contains(apiKey), isFalse);
      expect(result.contains('[masque]'), isTrue);
    });

    test('masque une chaîne base64 longue', () {
      const b64 = 'dGhpcyBpcyBhIHNlY3JldCB0b2tlbg=='; // 32 chars
      final result = SecureErrorHandler.sanitize('JWT: $b64');
      expect(result.contains(b64), isFalse);
      expect(result.contains('[masque]'), isTrue);
    });
  });

  group('SecureErrorHandler.sanitize — messages sûrs', () {
    test('préserve un message court sans info sensible', () {
      const msg = 'Erreur de connexion';
      final result = SecureErrorHandler.sanitize(msg);
      expect(result, equals(msg),
          reason: 'Un message court normal ne doit pas être modifié');
    });

    test('préserve un message d\'erreur générique', () {
      const msg = 'Timeout après 30 secondes';
      final result = SecureErrorHandler.sanitize(msg);
      expect(result, equals(msg));
    });

    test('ne modifie pas une chaîne alphanumérique courte (< 25 chars)', () {
      // Un mot de passe ou token court ne doit pas être forcément masqué
      // mais ici on vérifie surtout qu'une chaîne normale n'est pas altérée
      const msg = 'Code erreur: AUTH_FAILED';
      final result = SecureErrorHandler.sanitize(msg);
      expect(result, equals(msg),
          reason: 'Moins de 25 chars continus ne doit pas être masqué');
    });
  });

  group('SecureErrorHandler.sanitize — cas combinés', () {
    test('sanitise à la fois IP et chemin dans le même message', () {
      final result = SecureErrorHandler.sanitize(
        'Connexion de 192.168.0.1 vers /home/user/app échouée',
      );
      expect(result.contains('192.168'), isFalse);
      expect(result.contains('/home'), isFalse);
      expect(result.contains('[adresse]'), isTrue);
      expect(result.contains('[chemin]'), isTrue);
    });
  });
}
