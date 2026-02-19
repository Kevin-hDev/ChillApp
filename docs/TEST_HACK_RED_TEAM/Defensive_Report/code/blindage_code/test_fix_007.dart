// Test pour FIX-007 : Gestionnaire de nonces AES-GCM
import 'dart:typed_data';
import 'package:test/test.dart';

import 'fix_007_nonce_manager.dart';

void main() {
  group('NonceManager', () {
    test('genere des nonces de 12 octets', () {
      final mgr = NonceManager();
      final nonce = mgr.nextNonce();
      expect(nonce.length, equals(12));
    });

    test('genere des nonces uniques', () {
      final mgr = NonceManager();
      final nonces = <String>{};
      for (int i = 0; i < 1000; i++) {
        final nonce = mgr.nextNonce();
        final hex = nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        nonces.add(hex);
      }
      // 1000 nonces doivent tous etre uniques
      expect(nonces.length, equals(1000));
    });

    test('incrementer le compteur a chaque nonce', () {
      final mgr = NonceManager();
      expect(mgr.operationCount, equals(0));
      mgr.nextNonce();
      expect(mgr.operationCount, equals(1));
      mgr.nextNonce();
      expect(mgr.operationCount, equals(2));
    });

    test('remainingOperations decremente', () {
      final mgr = NonceManager();
      final initial = mgr.remainingOperations;
      mgr.nextNonce();
      expect(mgr.remainingOperations, equals(initial - 1));
    });

    test('needsRekey est false au debut', () {
      final mgr = NonceManager();
      expect(mgr.needsRekey, isFalse);
    });

    test('resetAfterRekey remet le compteur a zero', () {
      final mgr = NonceManager();
      for (int i = 0; i < 100; i++) {
        mgr.nextNonce();
      }
      expect(mgr.operationCount, equals(100));
      mgr.resetAfterRekey();
      expect(mgr.operationCount, equals(0));
      expect(mgr.needsRekey, isFalse);
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

    test('hexToken retourne un hex de bonne longueur', () {
      final token = SecureRandom.hexToken(16);
      expect(token.length, equals(32)); // 16 bytes = 32 hex chars
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), isTrue);
    });

    test('generateBytes produit des donnees non triviales', () {
      // Statistiquement, 32 bytes aleatoires ne devraient pas etre tous zeros
      final bytes = SecureRandom.generateBytes(32);
      expect(bytes.any((b) => b != 0), isTrue);
    });
  });
}
