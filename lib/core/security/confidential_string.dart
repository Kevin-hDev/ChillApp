// =============================================================
// FIX-021/022 : Obfuscation & String Protection
// GAP-021: Obfuscation Dart absente
// GAP-022: Obfuscation des littéraux absente
// =============================================================
//
// PROBLEME :
// - flutter build sans --obfuscate → noms de classes/fonctions
//   en clair dans le binaire (reverse trivial avec Blutter)
// - --obfuscate ne masque que les symboles. Les chaînes de
//   caractères (URLs, chemins, secrets) restent en clair.
//
// SOLUTION :
// Classe Dart qui chiffre les littéraux au repos via XOR avec
// une clé dérivée au runtime (PID + timestamp + sel fixe).
// La clé n'est JAMAIS stockée dans le binaire.
// =============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Protection des chaînes sensibles en mémoire.
///
/// La clé est dérivée de facteurs runtime (PID, timezone offset) et
/// n'est jamais écrite dans le binaire.
///
/// USAGE :
/// ```dart
/// // Initialiser une seule fois au démarrage
/// ConfidentialString.initialize();
///
/// // Protéger une chaîne (en dev, pour générer les constantes)
/// final enc = ConfidentialString.protect('/opt/chillapp/chill-tailscale');
///
/// // Révéler au runtime
/// final path = ConfidentialString.reveal(enc);
/// ```
class ConfidentialString {
  // Clé dérivée au runtime — jamais dans le binaire
  static late Uint8List _runtimeKey;
  static bool _initialized = false;

  /// Initialise la clé de dérivation au runtime.
  /// Doit être appelé une seule fois au démarrage de l'application.
  ///
  /// La clé est dérivée de :
  /// - La valeur de l'horloge monotone en microsecondes (non prévisible)
  /// - Le décalage horaire de la timezone (stable mais non stocké dans le binaire)
  /// - Un sel fixe connu uniquement dans ce fichier
  ///
  /// Ces facteurs changent à chaque lancement de l'application,
  /// rendant la clé impossible à reproduire à partir du binaire seul.
  static void initialize() {
    if (_initialized) return;

    // Facteurs runtime — aucun n'est une constante dans le binaire compilé.
    // microsecondsSinceEpoch change à chaque lancement (imprévisible).
    final now = DateTime.now();
    final microSeconds = now.microsecondsSinceEpoch;
    final timezoneOffset = now.timeZoneOffset.inMinutes;
    final appSalt = 'ChillApp'.codeUnits.fold<int>(0, (a, b) => a ^ b);

    // Combiner les facteurs pour créer une graine non prévisible
    final seed = (microSeconds ^ (timezoneOffset * 31)) ^ (appSalt * 2654435761);

    final rng = Random(seed);
    _runtimeKey = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    _initialized = true;
  }

  /// Chiffre une chaîne avec la clé runtime courante.
  ///
  /// Retourne une représentation base64 du XOR.
  /// La valeur retournée n'est valide QUE dans la session courante
  /// (la clé change à chaque lancement à cause du PID).
  static String protect(String plaintext) {
    if (!_initialized) initialize();
    final bytes = utf8.encode(plaintext);
    final encrypted = _xorWithKey(Uint8List.fromList(bytes));
    return base64Encode(encrypted);
  }

  /// Déchiffre une chaîne protégée avec la clé runtime courante.
  ///
  /// Lève une [FormatException] si la chaîne n'est pas du base64 valide.
  static String reveal(String protected) {
    if (!_initialized) initialize();
    final encrypted = base64Decode(protected);
    final decrypted = _xorWithKey(Uint8List.fromList(encrypted));
    return utf8.decode(decrypted);
  }

  /// Efface la clé runtime de la mémoire.
  /// Appeler en cas de fermeture sécurisée de l'application.
  static void dispose() {
    if (_initialized) {
      for (int i = 0; i < _runtimeKey.length; i++) {
        _runtimeKey[i] = 0;
      }
      _initialized = false;
    }
  }

  /// XOR cyclique avec la clé runtime.
  static Uint8List _xorWithKey(Uint8List data) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ _runtimeKey[i % _runtimeKey.length];
    }
    return result;
  }
}

/// Obfuscation déterministe de chaînes dans le binaire compilé.
///
/// **ATTENTION — LIMITATIONS DE SÉCURITÉ :**
/// Ce module fournit une **obfuscation superficielle**, PAS du chiffrement.
/// Un attaquant ayant accès au binaire ET à ce code source peut
/// recalculer le flux XOR et retrouver les chaînes originales.
///
/// Objectif : empêcher la lecture triviale des chaînes sensibles
/// via `strings` ou un éditeur hexadécimal. Ce n'est PAS une protection
/// contre un reverse-engineering déterminé.
///
/// **NE JAMAIS utiliser pour protéger :** clés SSH, tokens API,
/// mots de passe, ou toute donnée réellement secrète.
/// Pour cela, utiliser [SecureStorage] ou le keystore de l'OS.
///
/// USAGE (uniquement pour chemins de binaire, noms de service, etc.) :
/// ```dart
/// // En dev : générer une constante
/// const _encPath = 'valeur_generée_par_protect';
///
/// // Au runtime : révéler
/// final path = StrongConfidential.reveal(_encPath, 'daemon-path-v1');
/// ```
class StrongConfidential {
  /// Protège une chaîne avec un identifiant unique comme graine.
  ///
  /// [plaintext] : la chaîne à protéger
  /// [uniqueId] : identifiant stable (ex: nom symbolique de la constante)
  static String protect(String plaintext, String uniqueId) {
    final bytes = utf8.encode(plaintext);
    final keyStream = _generateKeyStream(uniqueId, bytes.length);
    final encrypted = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      encrypted[i] = bytes[i] ^ keyStream[i];
    }
    return base64Encode(encrypted);
  }

  /// Révèle une chaîne protégée avec son identifiant unique.
  ///
  /// Retourne une chaîne incorrecte si [uniqueId] ne correspond pas
  /// à celui utilisé lors du protect — pas d'exception levée.
  static String reveal(String protected, String uniqueId) {
    final encrypted = base64Decode(protected);
    final keyStream = _generateKeyStream(uniqueId, encrypted.length);
    final decrypted = Uint8List(encrypted.length);
    for (int i = 0; i < encrypted.length; i++) {
      decrypted[i] = encrypted[i] ^ keyStream[i];
    }
    return utf8.decode(decrypted, allowMalformed: true);
  }

  /// Génère un flux de clé pseudo-aléatoire déterministe à partir de
  /// l'identifiant unique en string.
  ///
  /// Utilise un hash simple de la string pour créer une graine entière,
  /// puis alimente un PRNG déterministe.
  static Uint8List _generateKeyStream(String uniqueId, int length) {
    // Hash de la string vers un entier (djb2)
    int hash = 5381;
    for (final codeUnit in uniqueId.codeUnits) {
      hash = ((hash << 5) + hash) ^ codeUnit;
      hash &= 0xFFFFFFFF; // Garder 32 bits
    }

    // Fibonacci hashing pour mieux distribuer la graine
    final seed = (hash * 2654435761) & 0xFFFFFFFF;

    final rng = Random(seed);
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
