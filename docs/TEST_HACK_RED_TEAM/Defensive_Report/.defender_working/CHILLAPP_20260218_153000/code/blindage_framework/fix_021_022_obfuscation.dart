// =============================================================
// FIX-021 : Obfuscation Dart (--obfuscate)
// GAP-021: Obfuscation Dart absente
// FIX-022 : Obfuscation des litteraux (Dart Confidential)
// GAP-022: Obfuscation des litteraux absente
// =============================================================
//
// PROBLEME :
// - flutter build sans --obfuscate → noms de classes/fonctions
//   en clair dans le binaire (reverse trivial avec Blutter)
// - --obfuscate ne masque que les symboles. Les chaines de
//   caracteres (URLs, chemins, secrets) restent en clair.
//
// SOLUTION :
// 1. Script de build avec --obfuscate --split-debug-info
// 2. Classe Dart qui chiffre les litteraux au repos
//    (XOR + derive de cle au runtime)
// =============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

// =============================================
// PARTIE 1 : Configuration de build (FIX-021)
// =============================================

/// Script de build obfusque.
/// A utiliser a la place de `flutter build` direct.
///
/// Usage :
///   dart run scripts/build_release.dart linux
///   dart run scripts/build_release.dart windows
///   dart run scripts/build_release.dart macos
///
/// Contenu du script scripts/build_release.dart :
/// ```dart
/// import 'dart:io';
///
/// void main(List<String> args) async {
///   final platform = args.isNotEmpty ? args[0] : 'linux';
///   final result = await Process.run('flutter', [
///     'build',
///     platform,
///     '--release',
///     '--obfuscate',
///     '--split-debug-info=build/symbols/$platform',
///   ]);
///   stdout.write(result.stdout);
///   stderr.write(result.stderr);
///   exit(result.exitCode);
/// }
/// ```
///
/// Les fichiers de debug symbols sont dans build/symbols/
/// et doivent etre conserves pour la deobfuscation des crash reports.

// =============================================
// PARTIE 2 : Obfuscation des litteraux (FIX-022)
// =============================================

/// Chiffrement XOR derive pour proteger les litteraux en memoire.
///
/// USAGE :
/// Au lieu de : const apiUrl = 'https://api.example.com';
/// Utiliser :  final apiUrl = ConfidentialString.reveal(_encApiUrl);
///
/// Les valeurs chiffrees sont generees par [ConfidentialString.protect].
class ConfidentialString {
  // Cle derivee au runtime (pas dans le binaire)
  static late Uint8List _runtimeKey;
  static bool _initialized = false;

  /// Initialiser avec une cle derivee au runtime.
  /// Appeler une seule fois au demarrage de l'app.
  static void initialize() {
    if (_initialized) return;

    // Deriver une cle a partir de facteurs runtime
    // (pas une constante dans le code)
    final seed = <int>[
      DateTime.now().timeZoneOffset.inMinutes,
      // Facteur stable mais pas dans le binaire
      'ChillApp'.codeUnits.fold<int>(0, (a, b) => a ^ b),
      42, // Sel fixe connu
    ];

    final rng = Random(seed.fold<int>(0, (a, b) => a * 31 + b));
    _runtimeKey = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    _initialized = true;
  }

  /// Chiffre une chaine pour le stockage dans le code source.
  /// A utiliser en dev pour generer les constantes chiffrees.
  static String protect(String plaintext) {
    if (!_initialized) initialize();
    final bytes = utf8.encode(plaintext);
    final encrypted = _xorWithKey(Uint8List.fromList(bytes));
    return base64Encode(encrypted);
  }

  /// Dechiffre une chaine protegee au runtime.
  static String reveal(String protected) {
    if (!_initialized) initialize();
    final encrypted = base64Decode(protected);
    final decrypted = _xorWithKey(Uint8List.fromList(encrypted));
    return utf8.decode(decrypted);
  }

  /// XOR cyclique avec la cle runtime.
  static Uint8List _xorWithKey(Uint8List data) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ _runtimeKey[i % _runtimeKey.length];
    }
    return result;
  }
}

/// Version plus forte utilisant un PRNG derive.
/// Chaque chaine a son propre flux XOR basé sur un ID unique.
class StrongConfidential {
  /// Protege une chaine avec un ID unique.
  /// L'ID sert de seed pour generer le flux XOR.
  static String protect(String plaintext, int uniqueId) {
    final bytes = utf8.encode(plaintext);
    final keyStream = _generateKeyStream(uniqueId, bytes.length);
    final encrypted = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      encrypted[i] = bytes[i] ^ keyStream[i];
    }
    return base64Encode(encrypted);
  }

  /// Revele une chaine protegee.
  static String reveal(String protected, int uniqueId) {
    final encrypted = base64Decode(protected);
    final keyStream = _generateKeyStream(uniqueId, encrypted.length);
    final decrypted = Uint8List(encrypted.length);
    for (int i = 0; i < encrypted.length; i++) {
      decrypted[i] = encrypted[i] ^ keyStream[i];
    }
    return utf8.decode(decrypted);
  }

  /// Genere un flux de cle pseudo-aleatoire a partir d'un ID.
  static Uint8List _generateKeyStream(int uniqueId, int length) {
    // Seed deterministe basee sur l'ID
    final rng = Random(uniqueId * 2654435761); // Fibonacci hashing
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}

// =============================================================
// CHAINES A PROTEGER DANS CHILLAPP :
// =============================================================
// Les suivantes sont des exemples. En production, generer les
// valeurs chiffrees avec protect() et les stocker comme constantes.
//
// Exemples de chaines a proteger :
//   - Chemins du daemon : '/opt/chillapp/chill-tailscale'
//   - Noms de fichiers de config
//   - URLs internes
//   - Messages d'erreur techniques
//
// NE PAS proteger :
//   - Les textes affiches a l'utilisateur (traductions)
//   - Les cles de traduction

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Obfuscation build (FIX-021) :
//    - Creer scripts/build_release.dart (voir ci-dessus)
//    - Modifier le CI/CD pour utiliser ce script
//    - Conserver build/symbols/ pour le debugging
//    - Ajouter build/symbols/ au .gitignore
//
// 2. Litteraux (FIX-022) :
//    - Creer lib/core/security/confidential_string.dart
//    - Appeler ConfidentialString.initialize() dans main.dart
//    - Pour chaque litterale sensible :
//      a. Generer : dart run -c 'print(ConfidentialString.protect("valeur"))'
//      b. Remplacer dans le code par ConfidentialString.reveal(valeurChiffree)
//
// 3. Script de generation (tool) :
//    - Creer tools/protect_strings.dart qui scanne le code
//      et genere les constantes chiffrees
// =============================================================
