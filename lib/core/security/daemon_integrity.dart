// =============================================================
// FIX-014 : Verification d'integrite du daemon Go
// GAP-024 : Binaire daemon non verifie avant execution (P0)
//
// PROBLEME : Le daemon Go (chill-tailscale) est lance sans
// aucune verification. Un attaquant pourrait remplacer le
// binaire par un programme malveillant.
//
// SOLUTION : Calculer le SHA-256 du binaire et le comparer
// avec un fichier .sha256 de reference avant tout demarrage.
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Verificateur d'integrite du binaire daemon.
///
/// Usage typique :
/// ```dart
/// final ok = await DaemonIntegrity.verifyBinary('/path/to/chill-tailscale');
/// if (!ok) {
///   // NE PAS demarrer le daemon
///   throw StateError('Integrite du daemon compromise');
/// }
/// ```
class DaemonIntegrity {
  DaemonIntegrity._(); // Classe utilitaire, pas d'instance

  /// Verifie l'integrite du binaire daemon par comparaison SHA-256.
  ///
  /// Lit le fichier `<binaryPath>.sha256` situe a cote du binaire.
  /// Compare le hash calcule avec le hash attendu en temps constant.
  ///
  /// Retourne `true` si le binaire est intact, `false` dans tous
  /// les autres cas (fichier .sha256 absent, hash incorrect, etc.).
  static Future<bool> verifyBinary(String binaryPath) async {
    final binaryFile = File(binaryPath);

    // Le binaire doit exister
    if (!await binaryFile.exists()) {
      _log('Binaire introuvable: $binaryPath');
      return false;
    }

    // Le fichier .sha256 de reference doit exister
    final hashFile = File('$binaryPath.sha256');
    if (!await hashFile.exists()) {
      _log('Fichier .sha256 introuvable: $binaryPath.sha256');
      return false;
    }

    // Lire le hash attendu (premiere ligne, sans espaces)
    final expectedHash = (await hashFile.readAsString()).trim().toLowerCase();
    if (expectedHash.isEmpty || expectedHash.length != 64) {
      _log('Contenu .sha256 invalide (doit etre un hash SHA-256 de 64 hex)');
      return false;
    }

    // Calculer le hash SHA-256 du binaire
    final bytes = await binaryFile.readAsBytes();
    final actualHash = sha256.convert(bytes).toString();

    // Comparaison en temps constant (protection contre timing attacks)
    final match = _constantTimeEquals(actualHash, expectedHash);

    if (!match) {
      _log('ALERTE SECURITE : Hash du daemon ne correspond pas !');
      _log('  Attendu  : $expectedHash');
      _log('  Calcule  : $actualHash');
    }

    return match;
  }

  /// Genere le fichier `.sha256` a cote du binaire.
  ///
  /// A utiliser une seule fois apres chaque build du daemon,
  /// dans un pipeline CI/CD de confiance.
  ///
  /// Le fichier genere contient uniquement le hash hexadecimal
  /// (64 caracteres), sans retour chariot superflu.
  static Future<void> generateHashFile(String binaryPath) async {
    final binaryFile = File(binaryPath);

    if (!await binaryFile.exists()) {
      throw FileSystemException('Binaire introuvable', binaryPath);
    }

    final bytes = await binaryFile.readAsBytes();
    final hash = sha256.convert(bytes).toString();

    final hashFile = File('$binaryPath.sha256');
    await hashFile.writeAsString(hash, encoding: utf8, flush: true);

    _log('Fichier .sha256 genere : $binaryPath.sha256');
    _log('  Hash : $hash');
  }

  /// Calcule et retourne le hash SHA-256 d'un fichier (utilitaire).
  static Future<String> computeHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Fichier introuvable', filePath);
    }
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  // -----------------------------------------------------------------
  // Helpers prives
  // -----------------------------------------------------------------

  /// Comparaison en temps constant pour eviter les attaques par timing.
  /// Deux chaines sont egales si et seulement si tous leurs octets
  /// le sont, sans court-circuit.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static void _log(String message) {
    debugPrint('[DaemonIntegrity] $message');
  }
}
