// =============================================================
// FIX-007 : Gestionnaire de nonces AES-GCM
// GAP-007 : Nonce manager pour futur chiffrement AES-GCM
// Cible : Nouveau composant (prerequis pour IPC chiffre en P5)
// =============================================================
//
// PROBLEME : Si du chiffrement AES-GCM est ajoute (IPC daemon,
// stockage securise), il faut un gestionnaire de nonces pour
// eviter la reutilisation. Reutiliser un nonce = l'attaquant
// recupere le flux XOR et dechiffre le trafic.
//
// SOLUTION : NonceManager avec compteur + partie aleatoire.
// Limite NIST : max 2^32 operations par cle.
// Rekey automatique a 90% de la limite.
// =============================================================

import 'dart:math';
import 'dart:typed_data';

/// Gestionnaire de nonces AES-GCM avec protection anti-reutilisation.
/// Chaque nonce est unique : 4 octets aleatoires + 8 octets compteur.
/// Le compteur est borne a 2^32 operations (recommandation NIST SP 800-38D).
class NonceManager {
  int _counter = 0;
  static const int maxOperations = 0xFFFFFFFF; // 2^32 - 1
  static const double _rekeyThreshold = 0.9; // 90% de la limite
  final Random _rng = Random.secure();

  /// Genere le prochain nonce unique de 12 octets.
  /// Leve une StateError si la limite est atteinte (rekey necessaire).
  ///
  /// Format du nonce (12 octets) :
  /// [4 octets aleatoires][8 octets compteur big-endian]
  Uint8List nextNonce() {
    if (_counter >= maxOperations) {
      throw StateError(
        'NonceManager: limite de $maxOperations operations atteinte. '
        'Rekey obligatoire avant de continuer.',
      );
    }

    final nonce = Uint8List(12);
    // 4 octets aleatoires pour l'unicite inter-sessions
    for (int i = 0; i < 4; i++) {
      nonce[i] = _rng.nextInt(256);
    }
    // 8 octets compteur (big-endian) pour l'unicite intra-session
    final bd = nonce.buffer.asByteData();
    bd.setInt64(4, _counter);
    _counter++;

    return nonce;
  }

  /// Indique si une rotation de cle est necessaire (>90% de la limite).
  bool get needsRekey => _counter >= (maxOperations * _rekeyThreshold).toInt();

  /// Nombre d'operations restantes avant la limite.
  int get remainingOperations => maxOperations - _counter;

  /// Nombre d'operations effectuees depuis le dernier reset.
  int get operationCount => _counter;

  /// Reset le compteur apres une rotation de cle.
  /// Appeler UNIQUEMENT apres avoir change la cle de chiffrement.
  void resetAfterRekey() {
    _counter = 0;
  }
}

/// Generateur de nombres aleatoires securise (wrapper).
/// Centralise l'usage de Random.secure() dans l'application.
class SecureRandom {
  static final Random _instance = Random.secure();

  /// Genere [length] octets aleatoires cryptographiquement surs.
  static Uint8List generateBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _instance.nextInt(256)),
    );
  }

  /// Genere un nonce AES-GCM de 12 octets.
  static Uint8List nonce12() => generateBytes(12);

  /// Genere un IV AES-CBC de 16 octets.
  static Uint8List iv16() => generateBytes(16);

  /// Genere une cle AES-256 de 32 octets.
  static Uint8List key32() => generateBytes(32);

  /// Genere un token hexadecimal de [byteLength] octets.
  static String hexToken(int byteLength) {
    final bytes = generateBytes(byteLength);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Ce composant sera utilise en P5 (blindage reseau/crypto) pour :
// 1. Chiffrement AES-GCM des messages IPC (GAP-035)
// 2. Rotation de cles automatique (GAP-029)
//
// Exemple d'usage futur :
//   final nonceMgr = NonceManager();
//   final nonce = nonceMgr.nextNonce();
//   final ciphertext = aesGcm.encrypt(plaintext, key: key, nonce: nonce);
//
//   if (nonceMgr.needsRekey) {
//     final newKey = SecureRandom.key32();
//     // ... negocier la nouvelle cle avec le daemon ...
//     nonceMgr.resetAfterRekey();
//   }
