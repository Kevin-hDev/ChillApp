// Test unitaire pour FIX-034 — SecureHeartbeat
// Lance avec : flutter test test/unit/security/test_secure_heartbeat.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/secure_heartbeat.dart';

// Clé fixe partagée au niveau global du fichier de test
// (pas dans main() pour éviter les problèmes de capture de closure)
final _testKey = List<int>.generate(32, (i) => i + 1);

// Helper : callback qui retourne la bonne réponse HMAC
Future<List<int>?> _goodCallback(List<int> challenge) async {
  return Hmac(sha256, _testKey).convert(challenge).bytes;
}

// Helper : callback qui retourne une mauvaise réponse
Future<List<int>?> _badCallback(List<int> challenge) async {
  return List.filled(32, 0xFF);
}

// Helper : comparaison en temps constant (testable indépendamment)
bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  int result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

void main() {
  // ===========================================================
  // Génération de challenges
  // ===========================================================

  group('Génération de challenges', () {
    test('100 challenges CSPRNG sont tous uniques', () {
      final random = Random.secure();
      final challenges = <String>{};

      for (int i = 0; i < 100; i++) {
        final bytes = Uint8List(32);
        for (int j = 0; j < 32; j++) {
          bytes[j] = random.nextInt(256);
        }
        final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        challenges.add(hex);
      }

      expect(challenges.length, equals(100),
          reason: '100 challenges CSPRNG doivent être uniques');
    });

    test('un challenge fait 32 bytes', () {
      final random = Random.secure();
      final bytes = Uint8List(32);
      for (int j = 0; j < 32; j++) {
        bytes[j] = random.nextInt(256);
      }
      expect(bytes.length, equals(32));
    });
  });

  // ===========================================================
  // Comparaison en temps constant
  // ===========================================================

  group('Comparaison en temps constant', () {
    test('deux tableaux identiques retournent true', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(_constantTimeEquals(a, b), isTrue);
    });

    test('deux tableaux différents retournent false', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 6]);
      expect(_constantTimeEquals(a, b), isFalse);
    });

    test('longueurs différentes retournent false', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(_constantTimeEquals(a, b), isFalse);
    });

    test('tableaux vides identiques retournent true', () {
      expect(_constantTimeEquals(Uint8List(0), Uint8List(0)), isTrue);
    });

    test('HMAC SHA-256 identiques comparent correctement', () {
      final key = Uint8List.fromList(_testKey);
      final challenge = Uint8List.fromList(List.generate(32, (i) => i));
      final bytes1 = Uint8List.fromList(Hmac(sha256, key).convert(challenge).bytes);
      final bytes2 = Uint8List.fromList(Hmac(sha256, key).convert(challenge).bytes);
      expect(_constantTimeEquals(bytes1, bytes2), isTrue);
    });

    test('HMAC SHA-256 différents comparent incorrectement', () {
      final key1 = Uint8List.fromList(_testKey);
      final key2 = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final challenge = Uint8List.fromList(List.generate(32, (i) => i));
      final bytes1 = Uint8List.fromList(Hmac(sha256, key1).convert(challenge).bytes);
      final bytes2 = Uint8List.fromList(Hmac(sha256, key2).convert(challenge).bytes);
      expect(_constantTimeEquals(bytes1, bytes2), isFalse);
    });
  });

  // ===========================================================
  // Transitions d'état
  // ===========================================================

  group('Transitions d\'état du heartbeat', () {
    test('état initial est stopped', () {
      final hb = SecureHeartbeat(sharedKey: _testKey);
      expect(hb.state, equals(HeartbeatState.stopped));
      hb.dispose();
    });

    test('un beat réussi change l\'état vers healthy', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);
      final result = await hb.beat(_goodCallback);
      expect(result.success, isTrue);
      expect(hb.state, equals(HeartbeatState.healthy));
      hb.dispose();
    });

    test('un beat échoué passe de stopped à degraded', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);
      await hb.beat(_badCallback);
      expect(hb.state, equals(HeartbeatState.degraded));
      hb.dispose();
    });

    test('3 échecs consécutifs passent à dead', () async {
      HeartbeatState? lastNewState;
      final hb = SecureHeartbeat(
        sharedKey: _testKey,
        maxFailures: 3,
        onStateChange: (old, newState) => lastNewState = newState,
      );

      for (int i = 0; i < 3; i++) {
        await hb.beat(_badCallback);
      }

      expect(hb.state, equals(HeartbeatState.dead));
      expect(lastNewState, equals(HeartbeatState.dead));
      hb.dispose();
    });

    test('un succès après dégradation revient à healthy', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey, maxFailures: 3);

      // 1 échec → degraded
      await hb.beat(_badCallback);
      expect(hb.state, equals(HeartbeatState.degraded));

      // 1 succès → healthy
      await hb.beat(_goodCallback);
      expect(hb.state, equals(HeartbeatState.healthy));
      hb.dispose();
    });
  });

  // ===========================================================
  // Compteur de failures et reset
  // ===========================================================

  group('Compteur d\'échecs et reset', () {
    test('le compteur se réinitialise après un succès', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey, maxFailures: 5);

      // 2 échecs
      await hb.beat(_badCallback);
      await hb.beat(_badCallback);
      expect(hb.state, equals(HeartbeatState.degraded));

      // 1 succès → compteur reset + retour healthy
      await hb.beat(_goodCallback);
      expect(hb.state, equals(HeartbeatState.healthy));

      // Après reset, 1 seul échec remet en degraded (pas dead)
      await hb.beat(_badCallback);
      expect(hb.state, equals(HeartbeatState.degraded));
      hb.dispose();
    });

    test('timeout retourne un résultat d\'échec', () async {
      final hb = SecureHeartbeat(
        sharedKey: _testKey,
        timeout: const Duration(milliseconds: 50),
      );

      // Mock qui dépasse le timeout
      final result = await hb.beat((challenge) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return List.filled(32, 0);
      });

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      hb.dispose();
    });

    test('historique garde les 100 derniers résultats au maximum', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);

      // Exécuter 110 beats échoués
      for (int i = 0; i < 110; i++) {
        await hb.beat(_badCallback);
      }

      expect(hb.history.length, equals(100));
      hb.dispose();
    });

    test('beat réussi enregistre une latence non nulle', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);
      final result = await hb.beat(_goodCallback);

      expect(result.success, isTrue);
      expect(result.latency, isNotNull);
      expect(result.latency!.inMicroseconds, greaterThanOrEqualTo(0));
      hb.dispose();
    });

    test('onStateChange est appelé lors de la transition', () async {
      HeartbeatState? capturedOld;
      HeartbeatState? capturedNew;

      final hb = SecureHeartbeat(
        sharedKey: _testKey,
        maxFailures: 3,
        onStateChange: (old, newState) {
          capturedOld = old;
          capturedNew = newState;
        },
      );

      await hb.beat(_badCallback);

      expect(capturedOld, isNotNull);
      expect(capturedNew, equals(HeartbeatState.degraded));
      hb.dispose();
    });
  });

  // ===========================================================
  // HMAC challenge-response
  // ===========================================================

  group('HMAC challenge-response', () {
    test('bonne réponse HMAC est acceptée', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);
      final result = await hb.beat(_goodCallback);

      expect(result.success, isTrue);
      expect(result.error, isNull);
      hb.dispose();
    });

    test('mauvaise réponse HMAC est rejetée', () async {
      final hb = SecureHeartbeat(sharedKey: _testKey);

      final wrongKey = List.generate(32, (i) => i + 200);
      final result = await hb.beat((challenge) async {
        return Hmac(sha256, wrongKey).convert(challenge).bytes;
      });

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      hb.dispose();
    });
  });
}
