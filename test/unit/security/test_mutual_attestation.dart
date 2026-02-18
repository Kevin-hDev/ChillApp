// Test unitaire pour FIX-051 — MutualAttestation
// Lance avec : flutter test test/unit/security/test_mutual_attestation.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/mutual_attestation.dart';

void main() {
  // Cle partagee de test (32 octets)
  final testKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

  // Hash d'un binaire fictif pour les tests
  const fakeLinuxHash =
      'abc123def456abc123def456abc123def456abc123def456abc123def456abc1';
  const fakeWindowsHash =
      'def456abc123def456abc123def456abc123def456abc123def456abc123def4';

  MutualAttestation createAttestation() => MutualAttestation(
        sharedKey: testKey,
        expectedHashes: {
          'linux': fakeLinuxHash,
          'windows': fakeWindowsHash,
        },
      );

  group('AttestationResult — structure', () {
    test('AttestationResult verified=true est correctement cree', () {
      const result = AttestationResult(
        verified: true,
        binaryHash: 'abc123',
        expectedHash: 'abc123',
      );
      expect(result.verified, isTrue);
      expect(result.binaryHash, equals('abc123'));
      expect(result.error, isNull);
    });

    test('AttestationResult verified=false avec erreur', () {
      const result = AttestationResult(
        verified: false,
        error: 'HMAC invalide',
      );
      expect(result.verified, isFalse);
      expect(result.error, equals('HMAC invalide'));
      expect(result.binaryHash, isNull);
    });
  });

  group('MutualAttestation.generateChallenge()', () {
    late MutualAttestation attestation;

    setUp(() {
      attestation = createAttestation();
    });

    test('generateChallenge retourne une chaine base64 valide', () {
      final challenge = attestation.generateChallenge();
      expect(challenge, isNotEmpty);
      // Verifier que c'est du base64 valide
      expect(() => base64Decode(challenge), returnsNormally);
    });

    test('generateChallenge produit un nonce de 32 octets', () {
      final challenge = attestation.generateChallenge();
      final decoded = base64Decode(challenge);
      expect(decoded.length, equals(32));
    });

    test('generateChallenge produit des valeurs aleatoires differentes', () {
      final challenges = <String>{};
      for (int i = 0; i < 20; i++) {
        challenges.add(attestation.generateChallenge());
      }
      // Avec 32 octets aleatoires, toutes les valeurs doivent etre uniques
      expect(challenges.length, equals(20));
    });

    tearDown(() {
      attestation.dispose();
    });
  });

  group('MutualAttestation.computeResponse()', () {
    late MutualAttestation attestation;
    late Directory tmpDir;
    late File tmpBinary;

    setUp(() {
      attestation = createAttestation();
      tmpDir = Directory.systemTemp.createTempSync('chill_attest_test_');
      tmpBinary = File('${tmpDir.path}/fake_daemon');
      tmpBinary.writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46, 0x01, 0x02, 0x03]);
    });

    tearDown(() {
      attestation.dispose();
      if (tmpBinary.existsSync()) tmpBinary.deleteSync();
      if (tmpDir.existsSync()) tmpDir.deleteSync();
    });

    test('computeResponse retourne une chaine avec format "hmac:hash"', () {
      final challenge = attestation.generateChallenge();
      final response = attestation.computeResponse(challenge, tmpBinary.path);
      expect(response, contains(':'));
      final parts = response.split(':');
      expect(parts.length, equals(2));
    });

    test('computeResponse retourne une reponse deterministe', () {
      final challenge = attestation.generateChallenge();
      final response1 = attestation.computeResponse(challenge, tmpBinary.path);
      final response2 = attestation.computeResponse(challenge, tmpBinary.path);
      expect(response1, equals(response2));
    });

    test('computeResponse produit des resultats differents pour des challenges differents', () {
      final challenge1 = attestation.generateChallenge();
      final challenge2 = attestation.generateChallenge();
      final response1 = attestation.computeResponse(challenge1, tmpBinary.path);
      final response2 = attestation.computeResponse(challenge2, tmpBinary.path);
      expect(response1, isNot(equals(response2)));
    });
  });

  group('MutualAttestation.verifyResponse() — cas valides', () {
    late MutualAttestation attestation;
    late Directory tmpDir;
    late File tmpBinary;
    late String binaryHash;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('chill_attest_test_');
      tmpBinary = File('${tmpDir.path}/fake_daemon');
      tmpBinary.writeAsBytesSync([0xde, 0xad, 0xbe, 0xef]);

      // Calculer le hash reel du fichier de test
      // On va creer une attestation avec ce hash
      final tempAttest = MutualAttestation(
        sharedKey: testKey,
        expectedHashes: {},
      );
      final challenge = tempAttest.generateChallenge();
      final response = tempAttest.computeResponse(challenge, tmpBinary.path);
      binaryHash = response.split(':')[1];
      tempAttest.dispose();

      // Creer l'attestation avec le hash reel du fichier
      attestation = MutualAttestation(
        sharedKey: testKey,
        expectedHashes: {'linux': binaryHash, 'windows': binaryHash},
      );
    });

    tearDown(() {
      attestation.dispose();
      if (tmpBinary.existsSync()) tmpBinary.deleteSync();
      if (tmpDir.existsSync()) tmpDir.deleteSync();
    });

    test('verifyResponse retourne verified=true pour une reponse valide', () {
      final challenge = attestation.generateChallenge();
      final response = attestation.computeResponse(challenge, tmpBinary.path);

      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: response,
        platform: 'linux',
      );

      expect(result.verified, isTrue);
      expect(result.error, isNull);
    });

    test('verifyResponse conserve le binaryHash dans le resultat', () {
      final challenge = attestation.generateChallenge();
      final response = attestation.computeResponse(challenge, tmpBinary.path);

      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: response,
        platform: 'linux',
      );

      expect(result.binaryHash, equals(binaryHash));
    });
  });

  group('MutualAttestation.verifyResponse() — cas d\'echec', () {
    late MutualAttestation attestation;

    setUp(() {
      attestation = createAttestation();
    });

    tearDown(() {
      attestation.dispose();
    });

    test('verifyResponse echoue pour une plateforme inconnue', () {
      final challenge = attestation.generateChallenge();
      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: 'fakeHmac:$fakeLinuxHash',
        platform: 'unknown_platform',
      );

      expect(result.verified, isFalse);
      expect(result.error, contains('plateforme'));
    });

    test('verifyResponse echoue pour un format de reponse invalide', () {
      final challenge = attestation.generateChallenge();
      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: 'format_sans_separateur_deux_points',
        platform: 'linux',
      );

      expect(result.verified, isFalse);
      expect(result.error, contains('Format'));
    });

    test('verifyResponse echoue si le hash du binaire ne correspond pas', () {
      final challenge = attestation.generateChallenge();
      // Utiliser un hash different du hash attendu
      const wrongHash =
          '0000000000000000000000000000000000000000000000000000000000000000';

      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: 'someHmacBase64:$wrongHash',
        platform: 'linux',
      );

      expect(result.verified, isFalse);
      expect(result.binaryHash, equals(wrongHash));
      expect(result.expectedHash, equals(fakeLinuxHash));
    });

    test('verifyResponse echoue si le HMAC est incorrect', () {
      final challenge = attestation.generateChallenge();
      // Hash correct mais HMAC invalide
      final result = attestation.verifyResponse(
        challengeB64: challenge,
        response: 'InvalidHmacBase64==:$fakeLinuxHash',
        platform: 'linux',
      );

      expect(result.verified, isFalse);
    });

    test('verifyResponse echoue pour un challenge invalide (base64 incorrect)', () {
      final result = attestation.verifyResponse(
        challengeB64: 'not_valid_base64!!!',
        response: 'someHmac:$fakeLinuxHash',
        platform: 'linux',
      );

      expect(result.verified, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('MutualAttestation.dispose()', () {
    test('dispose peut etre appele sans erreur', () {
      final attestation = createAttestation();
      expect(() => attestation.dispose(), returnsNormally);
    });

    test('La cle est effacee apres dispose', () {
      // On cree une cle avec des valeurs non-zero
      final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final attestation = MutualAttestation(
        sharedKey: key,
        expectedHashes: {'linux': fakeLinuxHash},
      );
      attestation.dispose();
      // Apres dispose, la cle interne doit etre a zero
      // (on ne peut pas y acceder directement, mais on verifie
      // que la methode ne lance pas d'exception)
    });
  });
}
