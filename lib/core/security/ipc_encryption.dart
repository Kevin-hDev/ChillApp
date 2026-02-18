// =============================================================
// FIX-035 : Chiffrement du protocole IPC
// GAP-035: Protocole IPC non securise (P0)
// Cible: lib/core/security/ipc_encryption.dart
// =============================================================
//
// PROBLEME : Les messages IPC entre l'app Flutter et le daemon Go
// sont du JSON brut sur stdin/stdout. Un processus malveillant
// peut les lire et les injecter.
//
// SOLUTION :
// - XOR stream cipher derive de SHA-256 en mode compteur (CTR)
// - HMAC-SHA256 Encrypt-then-MAC (integrite + authentification)
// - Nonce monotone 12 bytes (anti-replay)
// - Format : base64(nonce[12] + ciphertext + hmac_tag[32])
//
// Utilise uniquement : package:crypto et dart:typed_data
// =============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Echange de cle simplifie pour IPC local.
/// Combine les contributions des deux parties via HKDF-like SHA-256.
class IpcKeyExchange {
  /// Genere un secret partage a partir des contributions des deux parties.
  /// Format : SHA-256(localContribution || remoteContribution || "chillapp-ipc-v1")
  static Uint8List deriveSharedKey({
    required Uint8List localContribution,
    required Uint8List remoteContribution,
  }) {
    final label = utf8.encode('chillapp-ipc-v1');
    final combined = Uint8List(
      localContribution.length + remoteContribution.length + label.length,
    );
    combined.setAll(0, localContribution);
    combined.setAll(localContribution.length, remoteContribution);
    combined.setAll(
      localContribution.length + remoteContribution.length,
      label,
    );

    final hash = sha256.convert(combined);

    // Zeroiser la combinaison apres usage
    combined.fillRange(0, combined.length, 0);

    return Uint8List.fromList(hash.bytes);
  }

  /// Genere une contribution locale de 32 bytes via CSPRNG.
  static Uint8List generateContribution() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}

/// Chiffrement XOR-CTR + HMAC-SHA256 pour les messages IPC.
///
/// Format de sortie : base64(nonce[12] + ciphertext + hmac_tag[32])
///
/// Schema Encrypt-then-MAC :
///   1. nonce  = 8 bytes compteur monotone + 4 bytes random
///   2. keystream = SHA-256(encKey || nonce || counter) pour chaque bloc 32 bytes
///   3. ciphertext = plaintext XOR keystream
///   4. hmac_tag = HMAC-SHA256(macKey, nonce || ciphertext)
///
/// Note : Pour la production avec AES-GCM natif, remplacer par
/// package:pointycastle. Ce schema reste sur-mesure mais solide
/// pour un IPC local (stdin/stdout).
class IpcEncryption {
  final Uint8List _encryptionKey;
  final Uint8List _macKey;
  int _sendNonce = 0;

  /// Set des nonces complets (12 bytes base64) deja recus (anti-replay).
  final Set<String> _receivedNonces = {};

  /// Queue FIFO pour purge ordonnee des nonces recus.
  final List<String> _nonceQueue = [];

  /// Taille maximale du cache de nonces recus.
  static const int _maxNonceCache = 10000;

  /// Nombre de nonces purges a la fois (les 20% les plus anciens).
  static const int _purgeBatchSize = 2000;

  IpcEncryption._(this._encryptionKey, this._macKey);

  /// Cree une instance a partir d'un secret partage.
  /// Derive deux cles independantes : une pour le chiffrement, une pour le MAC.
  factory IpcEncryption.fromSharedSecret(Uint8List sharedSecret) {
    final encKey = sha256.convert(
      [...sharedSecret, ...utf8.encode('enc')],
    ).bytes;
    final macKey = sha256.convert(
      [...sharedSecret, ...utf8.encode('mac')],
    ).bytes;
    return IpcEncryption._(
      Uint8List.fromList(encKey),
      Uint8List.fromList(macKey),
    );
  }

  /// Chiffre et authentifie un message texte.
  ///
  /// [plaintext] : le message en clair (ex: JSON serialise)
  /// [key] : cle brute (ignoree ici, on utilise les cles derivees internes).
  ///         Parametre conserve pour compatibilite avec la signature de l'API.
  ///
  /// Retourne une chaine base64 : nonce(12) + ciphertext + hmac(32).
  String encrypt(String plaintext, [List<int>? key]) {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    // 1. Generer le nonce monotone
    final nonce = _generateNonce();

    // 2. Chiffrer via XOR keystream SHA-256-CTR
    final ciphertext = _xorKeystream(plaintextBytes, nonce);

    // 3. HMAC-SHA256 sur (nonce || ciphertext) — Encrypt-then-MAC
    final macData = Uint8List(nonce.length + ciphertext.length);
    macData.setAll(0, nonce);
    macData.setAll(nonce.length, ciphertext);
    final tag = Hmac(sha256, _macKey).convert(macData);

    // 4. Assembler : nonce(12) + ciphertext + tag(32)
    final output = Uint8List(12 + ciphertext.length + 32);
    output.setAll(0, nonce);
    output.setAll(12, ciphertext);
    output.setAll(12 + ciphertext.length, tag.bytes);

    return base64Encode(output);
  }

  /// Dechiffre et verifie un message.
  ///
  /// [ciphertext] : chaine base64 produite par [encrypt].
  /// [key] : cle brute (ignoree, parametre de compatibilite API).
  ///
  /// Retourne le texte en clair, ou leve une exception si :
  ///   - le format est invalide
  ///   - le HMAC ne correspond pas (falsification detectee)
  ///   - le nonce est rejoue (replay detecte)
  String decrypt(String ciphertext, [List<int>? key]) {
    final data = base64Decode(ciphertext);

    // Taille minimale : 12 (nonce) + 0 (vide) + 32 (tag)
    if (data.length < 44) {
      throw FormatException('Message IPC trop court (${data.length} bytes)');
    }

    // 1. Extraire les composants
    final nonce = Uint8List.sublistView(data, 0, 12);
    final encryptedData = Uint8List.sublistView(data, 12, data.length - 32);
    final receivedTag = Uint8List.sublistView(data, data.length - 32);

    // 2. Verifier le nonce anti-replay (nonce complet, pas juste le compteur)
    // Utilise le nonce complet (12 bytes) pour resister aux redemarrages.
    final nonceKey = base64Encode(nonce);
    if (_receivedNonces.contains(nonceKey)) {
      throw StateError('Replay detecte : nonce deja vu');
    }

    // 3. Verifier le HMAC en temps constant (Encrypt-then-MAC)
    final macData = Uint8List(nonce.length + encryptedData.length);
    macData.setAll(0, nonce);
    macData.setAll(nonce.length, encryptedData);
    final expectedTag = Hmac(sha256, _macKey).convert(macData);

    if (!_constantTimeEquals(
      Uint8List.fromList(expectedTag.bytes),
      receivedTag,
    )) {
      throw StateError('Authentification IPC echouee : HMAC invalide');
    }

    // 4. Dechiffrer (XOR est son propre inverse)
    final plaintextBytes = _xorKeystream(encryptedData, nonce);

    // 5. Enregistrer le nonce uniquement apres succes complet
    _receivedNonces.add(nonceKey);
    _nonceQueue.add(nonceKey);

    // Purge FIFO partielle : supprimer les 20% les plus anciens
    if (_receivedNonces.length > _maxNonceCache) {
      final toRemove = _nonceQueue.sublist(0, _purgeBatchSize);
      for (final old in toRemove) {
        _receivedNonces.remove(old);
      }
      _nonceQueue.removeRange(0, _purgeBatchSize);
    }

    return utf8.decode(plaintextBytes);
  }

  // ============================================================
  // Methodes internes
  // ============================================================

  /// Genere un nonce de 12 bytes : 8 bytes compteur monotone + 4 bytes random.
  Uint8List _generateNonce() {
    _sendNonce++;
    final nonce = Uint8List(12);

    // 8 bytes big-endian pour le compteur
    var value = _sendNonce;
    for (int i = 7; i >= 0; i--) {
      nonce[i] = value & 0xFF;
      value >>= 8;
    }

    // 4 bytes aleatoires (CSPRNG) pour eviter les collisions si le
    // compteur est remis a zero apres un redemarrage
    final random = Random.secure();
    for (int i = 8; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }

    return nonce;
  }

  /// XOR keystream derive de SHA-256(encryptionKey || nonce || counter).
  /// Produit des blocs de 32 bytes de keystream.
  Uint8List _xorKeystream(Uint8List data, Uint8List nonce) {
    final result = Uint8List(data.length);
    int offset = 0;
    int counter = 0;

    while (offset < data.length) {
      // Compteur 4 bytes big-endian
      final counterBytes = Uint8List(4);
      counterBytes[0] = (counter >> 24) & 0xFF;
      counterBytes[1] = (counter >> 16) & 0xFF;
      counterBytes[2] = (counter >> 8) & 0xFF;
      counterBytes[3] = counter & 0xFF;

      // Bloc de keystream : SHA-256(encKey || nonce || counter)
      final block = sha256.convert([
        ..._encryptionKey,
        ...nonce,
        ...counterBytes,
      ]).bytes;

      // XOR octet par octet
      for (int i = 0;
          i < block.length && offset < data.length;
          i++, offset++) {
        result[offset] = data[offset] ^ block[i];
      }

      counter++;
    }

    return result;
  }

  /// Comparaison en temps constant pour eviter les attaques timing.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Efface les cles et les caches en memoire (a appeler en fin de session).
  void dispose() {
    _encryptionKey.fillRange(0, _encryptionKey.length, 0);
    _macKey.fillRange(0, _macKey.length, 0);
    _receivedNonces.clear();
    _nonceQueue.clear();
  }
}
