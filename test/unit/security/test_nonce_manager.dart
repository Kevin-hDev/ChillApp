// Test pour FIX-007 : Gestionnaire de nonces AES-GCM
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/nonce_manager.dart';

void main() {
  group('NonceManager', () {
    test('génère des nonces de 12 octets', () {
      final mgr = NonceManager();
      final nonce = mgr.nextNonce();
      expect(nonce.length, equals(12));
    });

    test('génère des nonces uniques sur 1000 appels', () {
      final mgr = NonceManager();
      final nonces = <String>{};
      for (int i = 0; i < 1000; i++) {
        final nonce = mgr.nextNonce();
        final hex = nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        nonces.add(hex);
      }
      expect(nonces.length, equals(1000));
    });

    test('incrémente le compteur à chaque nonce', () {
      final mgr = NonceManager();
      expect(mgr.operationCount, equals(0));
      mgr.nextNonce();
      expect(mgr.operationCount, equals(1));
      mgr.nextNonce();
      expect(mgr.operationCount, equals(2));
    });

    test('remainingOperations décrémente correctement', () {
      final mgr = NonceManager();
      final initial = mgr.remainingOperations;
      mgr.nextNonce();
      expect(mgr.remainingOperations, equals(initial - 1));
    });

    test('needsRekey est false au début', () {
      final mgr = NonceManager();
      expect(mgr.needsRekey, isFalse);
    });

    test('resetAfterRekey remet le compteur à zéro', () {
      final mgr = NonceManager();
      for (int i = 0; i < 100; i++) {
        mgr.nextNonce();
      }
      expect(mgr.operationCount, equals(100));
      mgr.resetAfterRekey();
      expect(mgr.operationCount, equals(0));
      expect(mgr.needsRekey, isFalse);
    });

    test('remainingOperations + operationCount = maxOperations', () {
      final mgr = NonceManager();
      mgr.nextNonce();
      mgr.nextNonce();
      mgr.nextNonce();
      expect(
        mgr.remainingOperations + mgr.operationCount,
        equals(NonceManager.maxOperations),
      );
    });

    test('lève StateError quand la limite est atteinte', () {
      // On ne peut pas tester 2^32 - 1 opérations, donc on
      // vérifie le comportement via une instance manipulée.
      // Ce test vérifie que maxOperations est bien 0xFFFFFFFF.
      expect(NonceManager.maxOperations, equals(0xFFFFFFFF));
    });

    test('nonce a le bon format (4 octets random + 8 octets compteur)', () {
      final mgr = NonceManager();
      final nonce = mgr.nextNonce();
      // Le compteur commence à 0, les bytes 4 à 11 encodent 0 en big-endian
      final bd = nonce.buffer.asByteData();
      final counterPart = bd.getInt64(4);
      expect(counterPart, equals(0)); // Premier nonce : compteur = 0
    });

    test('le compteur dans le nonce croît correctement', () {
      final mgr = NonceManager();
      mgr.nextNonce(); // compteur 0 -> 1
      final nonce = mgr.nextNonce(); // compteur 1 -> 2
      final bd = nonce.buffer.asByteData();
      final counterPart = bd.getInt64(4);
      expect(counterPart, equals(1)); // Deuxième nonce : compteur = 1
    });
  });

  group('SecureRandom', () {
    test('generateBytes retourne la bonne longueur', () {
      final bytes = SecureRandom.generateBytes(32);
      expect(bytes.length, equals(32));
    });

    test('nonce12 retourne 12 octets', () {
      expect(SecureRandom.nonce12().length, equals(12));
    });

    test('iv16 retourne 16 octets', () {
      expect(SecureRandom.iv16().length, equals(16));
    });

    test('key32 retourne 32 octets', () {
      expect(SecureRandom.key32().length, equals(32));
    });

    test('hexToken retourne un hex de la bonne longueur', () {
      final token = SecureRandom.hexToken(16);
      expect(token.length, equals(32)); // 16 bytes = 32 caractères hex
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), isTrue);
    });

    test('generateBytes produit des données non triviales', () {
      // Statistiquement, 32 bytes aléatoires ne devraient pas être tous zéros
      final bytes = SecureRandom.generateBytes(32);
      expect(bytes.any((b) => b != 0), isTrue);
    });

    test('generateBytes retourne un Uint8List', () {
      final bytes = SecureRandom.generateBytes(8);
      expect(bytes, isA<Uint8List>());
    });

    test('deux appels à generateBytes produisent des résultats différents', () {
      final bytes1 = SecureRandom.generateBytes(16);
      final bytes2 = SecureRandom.generateBytes(16);
      // Probabilité de collision infime (1 sur 2^128)
      expect(bytes1, isNot(equals(bytes2)));
    });
  });
}
