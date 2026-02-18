// =============================================================
// FIX-007 : Gestionnaire de nonces AES-GCM
// GAP-007 : Nonce manager pour futur chiffrement AES-GCM
// Cible : Nouveau composant (prérequis pour IPC chiffré en P5)
// =============================================================
//
// PROBLÈME : Si du chiffrement AES-GCM est ajouté (IPC daemon,
// stockage sécurisé), il faut un gestionnaire de nonces pour
// éviter la réutilisation. Réutiliser un nonce = l'attaquant
// récupère le flux XOR et déchiffre le trafic.
//
// SOLUTION : NonceManager avec compteur + partie aléatoire.
// Limite NIST : max 2^32 opérations par clé.
// Rekey automatique à 90% de la limite.
// =============================================================

import 'dart:math';
import 'dart:typed_data';

/// Gestionnaire de nonces AES-GCM avec protection anti-réutilisation.
/// Chaque nonce est unique : 4 octets aléatoires + 8 octets compteur.
/// Le compteur est borné à 2^32 opérations (recommandation NIST SP 800-38D).
class NonceManager {
  int _counter = 0;
  static const int maxOperations = 0xFFFFFFFF; // 2^32 - 1
  static const double _rekeyThreshold = 0.9; // 90% de la limite
  final Random _rng = Random.secure();

  /// Génère le prochain nonce unique de 12 octets.
  /// Lève une StateError si la limite est atteinte (rekey nécessaire).
  ///
  /// Format du nonce (12 octets) :
  /// [4 octets aléatoires][8 octets compteur big-endian]
  Uint8List nextNonce() {
    if (_counter >= maxOperations) {
      throw StateError(
        'NonceManager: limite de $maxOperations opérations atteinte. '
        'Rekey obligatoire avant de continuer.',
      );
    }

    final nonce = Uint8List(12);
    // 4 octets aléatoires pour l'unicité inter-sessions
    for (int i = 0; i < 4; i++) {
      nonce[i] = _rng.nextInt(256);
    }
    // 8 octets compteur (big-endian) pour l'unicité intra-session
    final bd = nonce.buffer.asByteData();
    bd.setInt64(4, _counter);
    _counter++;

    return nonce;
  }

  /// Indique si une rotation de clé est nécessaire (>90% de la limite).
  bool get needsRekey => _counter >= (maxOperations * _rekeyThreshold).toInt();

  /// Nombre d'opérations restantes avant la limite.
  int get remainingOperations => maxOperations - _counter;

  /// Nombre d'opérations effectuées depuis le dernier reset.
  int get operationCount => _counter;

  /// Reset le compteur après une rotation de clé.
  /// Appeler UNIQUEMENT après avoir changé la clé de chiffrement.
  void resetAfterRekey() {
    _counter = 0;
  }
}

/// Générateur de nombres aléatoires sécurisé (wrapper).
/// Centralise l'usage de Random.secure() dans l'application.
class SecureRandom {
  static final Random _instance = Random.secure();

  /// Génère [length] octets aléatoires cryptographiquement sûrs.
  static Uint8List generateBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _instance.nextInt(256)),
    );
  }

  /// Génère un nonce AES-GCM de 12 octets.
  static Uint8List nonce12() => generateBytes(12);

  /// Génère un IV AES-CBC de 16 octets.
  static Uint8List iv16() => generateBytes(16);

  /// Génère une clé AES-256 de 32 octets.
  static Uint8List key32() => generateBytes(32);

  /// Génère un token hexadécimal de [byteLength] octets.
  static String hexToken(int byteLength) {
    final bytes = generateBytes(byteLength);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
