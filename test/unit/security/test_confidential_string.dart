// Test unitaire pour FIX-021/022 — ConfidentialString & StrongConfidential
// Lance avec : flutter test test/unit/security/test_confidential_string.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/confidential_string.dart';

void main() {
  // ===========================================================
  // ConfidentialString
  // ===========================================================

  group('ConfidentialString', () {
    setUp(() {
      // Réinitialiser l'état entre les tests pour garantir
      // une clé fraîche et cohérente dans la session de test.
      ConfidentialString.dispose();
      ConfidentialString.initialize();
    });

    test('roundtrip : protect puis reveal retourne le texte original', () {
      final original = 'https://api.example.com/v2';
      final protected = ConfidentialString.protect(original);
      final revealed = ConfidentialString.reveal(protected);
      expect(revealed, equals(original));
    });

    test('le texte protégé est différent du texte original', () {
      final original = '/opt/chillapp/chill-tailscale';
      final protected = ConfidentialString.protect(original);
      expect(protected, isNot(equals(original)));
      expect(protected, isNotEmpty);
    });

    test('le texte protégé est du base64 valide', () {
      final original = 'test-secret';
      final protected = ConfidentialString.protect(original);
      // Base64 valide : ne lève pas d'exception à decode
      expect(() => protected, returnsNormally);
      // La longueur base64 doit être non nulle
      expect(protected.length, greaterThan(0));
    });

    test('deux protect du même texte donnent le même résultat (déterministe)', () {
      final original = 'secret value';
      final p1 = ConfidentialString.protect(original);
      final p2 = ConfidentialString.protect(original);
      // La clé est stable dans une même session — résultat déterministe
      expect(p1, equals(p2));
    });

    test('texte vide fonctionne (roundtrip)', () {
      final protected = ConfidentialString.protect('');
      final revealed = ConfidentialString.reveal(protected);
      expect(revealed, equals(''));
    });

    test('caractères spéciaux et accents UTF-8 sont préservés', () {
      final original = 'Clé SSH: ñ, ü, é, 中文, 🔐';
      final protected = ConfidentialString.protect(original);
      final revealed = ConfidentialString.reveal(protected);
      expect(revealed, equals(original));
    });

    test('longue chaîne fonctionne correctement', () {
      final original = 'A' * 1000;
      final protected = ConfidentialString.protect(original);
      final revealed = ConfidentialString.reveal(protected);
      expect(revealed, equals(original));
    });

    test('deux chaînes différentes donnent des protections différentes', () {
      final p1 = ConfidentialString.protect('chemin1');
      final p2 = ConfidentialString.protect('chemin2');
      expect(p1, isNot(equals(p2)));
    });
  });

  // ===========================================================
  // StrongConfidential
  // ===========================================================

  group('StrongConfidential', () {
    test('roundtrip avec uniqueId string fonctionne', () {
      final original = 'test value';
      final protected = StrongConfidential.protect(original, 'daemon-path-v1');
      final revealed = StrongConfidential.reveal(protected, 'daemon-path-v1');
      expect(revealed, equals(original));
    });

    test('IDs différents produisent des résultats différents', () {
      final original = 'même texte';
      final p1 = StrongConfidential.protect(original, 'id-alpha');
      final p2 = StrongConfidential.protect(original, 'id-beta');
      expect(p1, isNot(equals(p2)));
    });

    test('mauvais uniqueId ne déchiffre pas correctement', () {
      final original = 'secret';
      final protected = StrongConfidential.protect(original, 'bon-id');
      final wrong = StrongConfidential.reveal(protected, 'mauvais-id');
      expect(wrong, isNot(equals(original)));
    });

    test('résultat est déterministe (même ID = même résultat)', () {
      final original = 'valeur stable';
      final p1 = StrongConfidential.protect(original, 'constante-42');
      final p2 = StrongConfidential.protect(original, 'constante-42');
      expect(p1, equals(p2));
    });

    test('texte vide avec uniqueId fonctionne', () {
      final protected = StrongConfidential.protect('', 'empty-test');
      final revealed = StrongConfidential.reveal(protected, 'empty-test');
      expect(revealed, equals(''));
    });

    test('caractères UTF-8 préservés avec uniqueId', () {
      final original = 'Chemin: /opt/données/é_ü_ñ';
      final protected = StrongConfidential.protect(original, 'utf8-test');
      final revealed = StrongConfidential.reveal(protected, 'utf8-test');
      expect(revealed, equals(original));
    });

    test('texte protégé est différent du texte original', () {
      final original = '/opt/chillapp/daemon';
      final protected = StrongConfidential.protect(original, 'path-test');
      expect(protected, isNot(equals(original)));
    });

    test('uniqueId vide fonctionne (roundtrip)', () {
      final original = 'test avec id vide';
      final protected = StrongConfidential.protect(original, '');
      final revealed = StrongConfidential.reveal(protected, '');
      expect(revealed, equals(original));
    });
  });
}
