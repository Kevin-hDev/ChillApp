// =============================================================
// FIX-046 : Duress PIN (mot de passe sous contrainte)
// GAP-046: Plausible deniability absente (P2)
// Cible: lib/core/security/duress_pin.dart (nouveau)
// =============================================================
//
// PROBLEME : Si l'utilisateur est force de donner son PIN,
// l'attaquant accede a toutes les donnees.
//
// SOLUTION :
// 1. Un second PIN "duress" configurable par l'utilisateur
// 2. Le duress PIN ouvre une interface factice
// 3. Envoie une alerte silencieuse
// 4. Les vraies donnees sont cachees
// 5. Comparaison en temps constant (pas de timing attack)
// =============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Resultat de la verification du PIN.
enum PinVerificationResult {
  /// PIN correct — acces normal.
  normal,

  /// PIN duress — mode factice + alerte.
  duress,

  /// PIN incorrect.
  invalid,
}

/// Donnees factices a afficher en mode duress.
class DuressData {
  /// Fausses connexions SSH (vides ou factices).
  static const List<Map<String, String>> fakeSshHosts = [
    {'name': 'Home PC', 'status': 'offline'},
  ];

  /// Faux parametres (tout desactive).
  static const Map<String, bool> fakeSettings = {
    'firewall': true,
    'tailscale': false,
    'ssh': false,
  };
}

/// Gestionnaire de duress PIN.
class DuressPin {
  /// Verifie un PIN entre le PIN normal et le PIN duress.
  /// Les deux comparaisons sont TOUJOURS effectuees (temps constant).
  static PinVerificationResult verify({
    required String enteredPin,
    required String normalPinHash,
    required String duressPinHash,
    required String salt,
    required int iterations,
  }) {
    // Calculer le hash du PIN entre (PBKDF2)
    final enteredHash = _hashPin(enteredPin, salt, iterations);

    // Comparaison en temps constant pour les DEUX hashes
    // (toujours comparer les deux, meme si le premier match)
    final isNormal = _constantTimeEquals(enteredHash, normalPinHash);
    final isDuress = _constantTimeEquals(enteredHash, duressPinHash);

    // Evaluer le resultat
    if (isNormal) return PinVerificationResult.normal;
    if (isDuress) return PinVerificationResult.duress;
    return PinVerificationResult.invalid;
  }

  /// Genere le hash d'un PIN (PBKDF2-HMAC-SHA256).
  static String _hashPin(String pin, String salt, int iterations) {
    final pinBytes = utf8.encode(pin);
    final saltBytes = utf8.encode(salt);

    // PBKDF2 simplifie (utiliser le meme que lock_provider.dart)
    var hmacKey = Uint8List.fromList(pinBytes);
    var block = Uint8List.fromList([...saltBytes, 0, 0, 0, 1]);

    var u = Hmac(sha256, hmacKey).convert(block).bytes;
    var result = List<int>.from(u);

    for (int i = 1; i < iterations; i++) {
      u = Hmac(sha256, hmacKey).convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }

    return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

// =============================================================
// INTEGRATION dans lock_provider.dart :
// =============================================================
//
// 1. A la configuration du PIN, proposer un duress PIN :
//   "Voulez-vous configurer un code de secours ?
//    Ce code montrera de fausses donnees si vous etes force
//    de donner votre code."
//
// 2. Stocker le hash du duress PIN dans le secure storage :
//   await secureStorage.write('duress_pin_hash', duressHash);
//
// 3. A la verification du PIN :
//   final result = DuressPin.verify(
//     enteredPin: entered,
//     normalPinHash: storedNormalHash,
//     duressPinHash: storedDuressHash ?? '',
//     salt: storedSalt,
//     iterations: 100000,
//   );
//
//   switch (result) {
//     case PinVerificationResult.normal:
//       // Acces normal
//       break;
//     case PinVerificationResult.duress:
//       // Mode factice
//       auditLog.log(SecurityAction.duressMode, 'Duress PIN utilise');
//       navigateToFakeInterface();
//       break;
//     case PinVerificationResult.invalid:
//       tarpit.recordFailure('pin');
//       break;
//   }
// =============================================================
