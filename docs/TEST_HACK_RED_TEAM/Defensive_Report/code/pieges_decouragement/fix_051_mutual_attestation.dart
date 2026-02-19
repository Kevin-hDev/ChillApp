// =============================================================
// FIX-051 : Attestation mutuelle app/daemon
// GAP-051: Attestation mutuelle app/daemon absente (P2)
// Cible: lib/core/security/mutual_attestation.dart (nouveau)
// =============================================================
//
// PROBLEME : L'app fait confiance au daemon sans verification
// d'identite. Un faux daemon peut se substituer au vrai.
//
// SOLUTION :
// 1. Challenge-response base sur le hash signe du binaire
// 2. L'app envoie un nonce au daemon
// 3. Le daemon repond avec HMAC(nonce + binaryHash, sharedKey)
// 4. L'app verifie que le hash correspond au binaire attendu
// 5. Verification bidirectionnelle
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Resultat de l'attestation.
class AttestationResult {
  final bool verified;
  final String? binaryHash;
  final String? expectedHash;
  final String? error;

  const AttestationResult({
    required this.verified,
    this.binaryHash,
    this.expectedHash,
    this.error,
  });
}

/// Attestation mutuelle entre l'app Flutter et le daemon Go.
class MutualAttestation {
  final Uint8List _sharedKey;
  final Map<String, String> _expectedHashes;

  MutualAttestation({
    required Uint8List sharedKey,
    required Map<String, String> expectedHashes,
  }) : _sharedKey = Uint8List.fromList(sharedKey),
       _expectedHashes = Map.from(expectedHashes);

  /// Genere un challenge d'attestation.
  String generateChallenge() {
    final random = Random.secure();
    final nonce = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      nonce[i] = random.nextInt(256);
    }
    return base64Encode(nonce);
  }

  /// Calcule la reponse a un challenge (cote daemon).
  /// Le daemon doit calculer :
  ///   HMAC-SHA256(nonce + SHA256(binary), sharedKey)
  String computeResponse(String challengeB64, String binaryPath) {
    final nonce = base64Decode(challengeB64);
    final binaryHash = _hashFile(binaryPath);

    final payload = Uint8List(nonce.length + binaryHash.length);
    payload.setAll(0, nonce);
    payload.setAll(nonce.length, utf8.encode(binaryHash));

    final hmac = Hmac(sha256, _sharedKey).convert(payload);
    return '${base64Encode(hmac.bytes)}:$binaryHash';
  }

  /// Verifie la reponse du daemon.
  AttestationResult verifyResponse({
    required String challengeB64,
    required String response,
    required String platform,
  }) {
    try {
      final parts = response.split(':');
      if (parts.length != 2) {
        return const AttestationResult(
          verified: false,
          error: 'Format de reponse invalide',
        );
      }

      final hmacB64 = parts[0];
      final claimedHash = parts[1];

      // Verifier le hash attendu
      final expectedHash = _expectedHashes[platform];
      if (expectedHash == null) {
        return AttestationResult(
          verified: false,
          binaryHash: claimedHash,
          error: 'Pas de hash attendu pour la plateforme $platform',
        );
      }

      if (!_constantTimeEquals(claimedHash, expectedHash)) {
        return AttestationResult(
          verified: false,
          binaryHash: claimedHash,
          expectedHash: expectedHash,
          error: 'Hash du binaire ne correspond pas (daemon modifie ?)',
        );
      }

      // Verifier le HMAC
      final nonce = base64Decode(challengeB64);
      final payload = Uint8List(nonce.length + claimedHash.length);
      payload.setAll(0, nonce);
      payload.setAll(nonce.length, utf8.encode(claimedHash));

      final expectedHmac = Hmac(sha256, _sharedKey).convert(payload);
      final expectedHmacB64 = base64Encode(expectedHmac.bytes);

      if (!_constantTimeEquals(hmacB64, expectedHmacB64)) {
        return AttestationResult(
          verified: false,
          binaryHash: claimedHash,
          expectedHash: expectedHash,
          error: 'HMAC invalide (cle partagee incorrecte ?)',
        );
      }

      return AttestationResult(
        verified: true,
        binaryHash: claimedHash,
        expectedHash: expectedHash,
      );
    } catch (e) {
      return AttestationResult(
        verified: false,
        error: 'Erreur d\'attestation: $e',
      );
    }
  }

  /// Calcule le SHA-256 d'un fichier binaire.
  static String _hashFile(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  /// Calcule le hash du binaire de l'app courante.
  static Future<String> hashCurrentBinary() async {
    final execPath = Platform.resolvedExecutable;
    return _hashFile(execPath);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  void dispose() {
    _sharedKey.fillRange(0, _sharedKey.length, 0);
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Au demarrage du daemon :
//
//   final attestation = MutualAttestation(
//     sharedKey: ipcSharedKey,
//     expectedHashes: {
//       'linux': 'sha256_du_binaire_linux_release',
//       'windows': 'sha256_du_binaire_windows_release',
//       'macos': 'sha256_du_binaire_macos_release',
//     },
//   );
//
//   // 1. Envoyer un challenge au daemon
//   final challenge = attestation.generateChallenge();
//   daemon.stdin.writeln(jsonEncode({'type': 'attest', 'challenge': challenge}));
//
//   // 2. Recevoir la reponse
//   final response = await daemon.stdout.first;
//   final json = jsonDecode(response);
//
//   // 3. Verifier
//   final result = attestation.verifyResponse(
//     challengeB64: challenge,
//     response: json['attestation'],
//     platform: Platform.operatingSystem,
//   );
//
//   if (!result.verified) {
//     // FAIL CLOSED — daemon non verifie
//     failGuard.forceOpen('Attestation echouee: ${result.error}');
//     killDaemon();
//   }
// =============================================================
