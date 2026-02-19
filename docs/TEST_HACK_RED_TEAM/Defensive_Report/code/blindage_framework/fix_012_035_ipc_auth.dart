// =============================================================
// FIX-012 : Authentification et integrite IPC daemon
// GAP-012: IPC daemon non authentifie ni chiffre (P0)
// GAP-024: Verification d'integrite du daemon Go (P0)
// Cible: lib/features/tailscale/tailscale_provider.dart
// =============================================================
//
// PROBLEME : Le daemon Go est execute sans verification
// d'integrite. L'IPC est du JSON clair sans authentification.
// Tout processus peut injecter des commandes.
//
// SOLUTION :
// 1. Hash SHA-256 du binaire verifie avant execution
// 2. HMAC-SHA256 sur chaque message IPC
// 3. Nonce anti-replay dans chaque message
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:math';

/// Verificateur d'integrite du binaire daemon.
class DaemonIntegrityVerifier {
  /// Hashes SHA-256 attendus des binaires daemon par OS.
  /// A mettre a jour a chaque release du daemon.
  /// En production, ces hashes seraient dans un fichier signe.
  final Map<String, String> _expectedHashes;

  DaemonIntegrityVerifier(this._expectedHashes);

  /// Verifie le hash SHA-256 du binaire daemon avant execution.
  /// Retourne true si le hash correspond, false sinon.
  Future<bool> verify(String binaryPath) async {
    final file = File(binaryPath);
    if (!await file.exists()) return false;

    // Calculer le hash SHA-256 du binaire
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();

    // Determiner le hash attendu selon l'OS
    final os = Platform.operatingSystem; // 'linux', 'macos', 'windows'
    final expected = _expectedHashes[os];

    if (expected == null) return false;
    return _constantTimeEquals(hash, expected);
  }

  /// Comparaison en temps constant.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Protocole IPC authentifie avec HMAC et nonce.
/// Chaque message est signe avec un secret partage
/// et protege contre le replay par un nonce unique.
class AuthenticatedIPC {
  final Uint8List _sharedSecret;
  final Set<String> _usedNonces = {};
  static const int _nonceSize = 16;
  static const int _maxNonceCache = 10000;

  /// Cree le protocole IPC avec un secret partage.
  /// Le secret est genere au demarrage et echange via un
  /// canal securise (ex: fichier avec permissions 0600).
  AuthenticatedIPC(this._sharedSecret);

  /// Genere un secret partage aleatoire.
  static Uint8List generateSecret() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
  }

  /// Signe un message JSON avec HMAC-SHA256 + nonce.
  /// Retourne le message enveloppe avec signature et nonce.
  String signMessage(Map<String, dynamic> payload) {
    // Generer un nonce unique
    final rng = Random.secure();
    final nonceBytes = Uint8List.fromList(
      List.generate(_nonceSize, (_) => rng.nextInt(256)),
    );
    final nonce = base64Encode(nonceBytes);

    // Construire le message avec nonce et timestamp
    final message = {
      'payload': payload,
      'nonce': nonce,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final messageJson = jsonEncode(message);

    // Calculer le HMAC
    final hmac = Hmac(sha256, _sharedSecret);
    final mac = hmac.convert(utf8.encode(messageJson)).toString();

    // Envelopper avec la signature
    return jsonEncode({
      'message': messageJson,
      'mac': mac,
    });
  }

  /// Verifie et extrait un message signe.
  /// Retourne le payload si valide, null sinon.
  Map<String, dynamic>? verifyMessage(String signedMessage) {
    try {
      final envelope = jsonDecode(signedMessage) as Map<String, dynamic>;
      final messageJson = envelope['message'] as String;
      final receivedMac = envelope['mac'] as String;

      // Verifier le HMAC en temps constant
      final hmac = Hmac(sha256, _sharedSecret);
      final expectedMac = hmac.convert(utf8.encode(messageJson)).toString();

      if (!_constantTimeEquals(expectedMac, receivedMac)) {
        return null; // Signature invalide
      }

      // Extraire le message
      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      // Verifier le nonce (anti-replay)
      final nonce = message['nonce'] as String;
      if (_usedNonces.contains(nonce)) {
        return null; // Replay detecte
      }

      // Verifier le timestamp (fenetre de 30 secondes)
      final timestamp = DateTime.parse(message['timestamp'] as String);
      final age = DateTime.now().toUtc().difference(timestamp);
      if (age.abs() > const Duration(seconds: 30)) {
        return null; // Message trop ancien
      }

      // Enregistrer le nonce
      _usedNonces.add(nonce);
      if (_usedNonces.length > _maxNonceCache) {
        _usedNonces.clear(); // Reset pour eviter la fuite memoire
      }

      return message['payload'] as Map<String, dynamic>;
    } catch (_) {
      return null; // Message invalide
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

// =============================================================
// INTEGRATION dans tailscale_provider.dart :
// =============================================================
//
// 1. Avant Process.start() :
//    final verifier = DaemonIntegrityVerifier({'linux': 'sha256_hash...'});
//    if (!await verifier.verify(daemonPath)) {
//      // ALERTE : daemon modifie, refuser de demarrer
//      throw SecurityException('Daemon integrity check failed');
//    }
//
// 2. Initialiser l'IPC authentifie :
//    final secret = AuthenticatedIPC.generateSecret();
//    // Ecrire le secret dans un fichier temp avec permissions 0600
//    final ipc = AuthenticatedIPC(secret);
//
// 3. Pour envoyer un message :
//    final signed = ipc.signMessage({'action': 'connect', 'host': host});
//    _process!.stdin.writeln(signed);
//
// 4. Pour recevoir un message :
//    final payload = ipc.verifyMessage(receivedLine);
//    if (payload == null) { /* message invalide, ignorer */ }
