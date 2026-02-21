// =============================================================
// FIX-025 : Canary values et tripwires
// GAP-025 : Canary values et tripwires absents
// Cible   : lib/core/security/canary_values.dart
// =============================================================
//
// PROBLEME : Aucun moyen de detecter si la config, les fichiers
// ou la memoire ont ete modifies par un attaquant.
//
// SOLUTION :
// 1. Canary values en memoire (detecte corruption memoire)
// 2. Fichier canary sur disque (detecte acces non autorise)
// 3. Checksum de la configuration (detecte tampering)
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Etat d'un canary.
enum CanaryStatus {
  /// Canary intact, pas de tampering detecte.
  intact,

  /// Canary lu recemment (acces suspect).
  accessed,

  /// Canary modifie (tampering confirme).
  modified,

  /// Canary supprime (tampering confirme).
  deleted,
}

// =============================================================
// MEMOIRE
// =============================================================

/// Canary en memoire : valeur sentinelle qui detecte la corruption.
///
/// Genere 64 octets aleatoires a la creation et calcule leur SHA-256.
/// [verify] compare le hash courant au hash attendu en temps constant
/// pour resister aux attaques par timing.
class MemoryCanary {
  final Uint8List _canaryValue;
  final String _expectedHash;

  MemoryCanary._({
    required Uint8List canaryValue,
    required String expectedHash,
  })  : _canaryValue = canaryValue,
        _expectedHash = expectedHash;

  /// Cree un nouveau canary avec une valeur completement aleatoire.
  factory MemoryCanary.create() {
    final rng = Random.secure();
    final value = Uint8List.fromList(
      List.generate(64, (_) => rng.nextInt(256)),
    );
    final hash = sha256.convert(value).toString();
    return MemoryCanary._(canaryValue: value, expectedHash: hash);
  }

  /// Verifie que le canary n'a pas ete modifie.
  ///
  /// Retourne false si une corruption memoire est detectee.
  /// La comparaison est effectuee en temps constant pour eviter
  /// les attaques par timing.
  bool verify() {
    final currentHash = sha256.convert(_canaryValue).toString();
    if (currentHash.length != _expectedHash.length) return false;

    // Comparaison en temps constant (XOR bit a bit)
    int diff = 0;
    for (int i = 0; i < currentHash.length; i++) {
      diff |= currentHash.codeUnitAt(i) ^ _expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}

// =============================================================
// FICHIER
// =============================================================

/// Canary fichier : detecte les acces non autorises au disque.
///
/// Deploie un fichier avec du contenu qui semble interessant pour
/// un attaquant (fausses cles API, faux mots de passe). Toute
/// modification ou suppression est un signe de compromission.
class FileCanary {
  final String _canaryPath;
  final String _expectedHash;

  FileCanary._({
    required String canaryPath,
    required String expectedHash,
  })  : _canaryPath = canaryPath,
        _expectedHash = expectedHash;

  /// Chemin du fichier canary.
  String get canaryPath => _canaryPath;

  /// Cree un fichier canary sur disque.
  ///
  /// Le contenu ressemble a des identifiants reels pour attirer
  /// un attaquant et detecter l'acces. Permissions 600 appliquees
  /// automatiquement sur Linux et macOS.
  static Future<FileCanary> deploy({
    required String directory,
    String filename = '.cache_config.dat',
  }) async {
    final canaryPath = '$directory/$filename';

    // Contenu factice qui semble precieux
    final content = jsonEncode({
      'api_key': _generateFakeToken(),
      'db_password': _generateFakeToken(),
      'admin_token': _generateFakeToken(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final hash = sha256.convert(utf8.encode(content)).toString();

    final file = File(canaryPath);
    await file.writeAsString(content, flush: true);

    // Permissions restrictives (Linux / macOS)
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', canaryPath]);
    }

    return FileCanary._(
      canaryPath: canaryPath,
      expectedHash: hash,
    );
  }

  /// Verifie si le fichier canary a ete supprime ou modifie.
  ///
  /// Retourne [CanaryStatus.deleted] si le fichier n'existe plus,
  /// [CanaryStatus.modified] si son contenu a change,
  /// [CanaryStatus.accessed] s'il a ete lu recemment (Unix uniquement),
  /// [CanaryStatus.intact] sinon.
  Future<CanaryStatus> check() async {
    final file = File(_canaryPath);

    if (!await file.exists()) {
      return CanaryStatus.deleted;
    }

    final content = await file.readAsString();
    final hash = sha256.convert(utf8.encode(content)).toString();

    if (hash != _expectedHash) {
      return CanaryStatus.modified;
    }

    // Verifier la date d'acces sur Unix (atime)
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final stat = await file.stat();
        final accessAge = DateTime.now().difference(stat.accessed);
        if (accessAge.inSeconds < 60) {
          return CanaryStatus.accessed;
        }
      } catch (_) {
        // Si la lecture du stat echoue, on ne bloque pas
      }
    }

    return CanaryStatus.intact;
  }

  /// Genere un faux token qui ressemble a un vrai (base64 24 octets).
  static String _generateFakeToken() {
    final rng = Random.secure();
    final bytes = List.generate(24, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }
}

// =============================================================
// CONFIG
// =============================================================

/// Checksum SHA-256 de fichiers de configuration.
///
/// Capture les empreintes des fichiers a un instant T et permet
/// de detecter toute modification ulterieure.
class ConfigCanary {
  final Map<String, String> _checksums;

  ConfigCanary._(this._checksums);

  /// Nombre de fichiers surveilles.
  int get fileCount => _checksums.length;

  /// Capture les checksums de tous les fichiers de config indiques.
  ///
  /// Les fichiers inexistants sont ignores silencieusement.
  static Future<ConfigCanary> snapshot({
    required List<String> configPaths,
  }) async {
    final checksums = <String, String>{};

    for (final path in configPaths) {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsBytes();
        checksums[path] = sha256.convert(content).toString();
      }
    }

    return ConfigCanary._(checksums);
  }

  /// Verifie si un ou plusieurs fichiers de config ont ete modifies.
  ///
  /// Retourne la liste des chemins de fichiers modifies ou supprimes.
  /// Une liste vide signifie que tout est intact.
  Future<List<String>> verify() async {
    final modified = <String>[];

    for (final entry in _checksums.entries) {
      final file = File(entry.key);
      if (!await file.exists()) {
        modified.add(entry.key);
        continue;
      }

      final content = await file.readAsBytes();
      final currentHash = sha256.convert(content).toString();
      if (currentHash != entry.value) {
        modified.add(entry.key);
      }
    }

    return modified;
  }
}

// =============================================================
// GESTIONNAIRE GLOBAL
// =============================================================

/// Gestionnaire centralise de tous les canaries de l'application.
///
/// Coordonne le deploiement et la verification periodique des
/// trois types de canaries : memoire, fichier et config.
class CanaryManager {
  MemoryCanary? _memoryCanary;
  FileCanary? _fileCanary;
  ConfigCanary? _configCanary;

  /// Callback invoque quand un canary est declenche.
  ///
  /// Parametres : type du canary ('memory', 'file', 'config')
  /// et statut detecte.
  final void Function(String type, CanaryStatus status)? onTriggered;

  CanaryManager({this.onTriggered});

  /// Deploie tous les canaries.
  ///
  /// [appDataDir]  : Repertoire de donnees de l'app (pour le fichier canary)
  /// [configPaths] : Liste des fichiers de config a surveiller
  Future<void> deployAll({
    required String appDataDir,
    required List<String> configPaths,
  }) async {
    _memoryCanary = MemoryCanary.create();
    _fileCanary = await FileCanary.deploy(directory: appDataDir);
    _configCanary = await ConfigCanary.snapshot(configPaths: configPaths);
  }

  /// Verifie tous les canaries deployes.
  ///
  /// Appelle [onTriggered] pour chaque anomalie detectee.
  /// Retourne true si tous les canaries sont intacts.
  Future<bool> verifyAll() async {
    bool allOk = true;

    // 1. Canary memoire
    if (_memoryCanary != null && !_memoryCanary!.verify()) {
      onTriggered?.call('memory', CanaryStatus.modified);
      allOk = false;
    }

    // 2. Canary fichier
    if (_fileCanary != null) {
      final status = await _fileCanary!.check();
      if (status != CanaryStatus.intact) {
        onTriggered?.call('file', status);
        allOk = false;
      }
    }

    // 3. Canary config
    if (_configCanary != null) {
      final modifiedFiles = await _configCanary!.verify();
      if (modifiedFiles.isNotEmpty) {
        onTriggered?.call('config', CanaryStatus.modified);
        allOk = false;
      }
    }

    return allOk;
  }

  /// Indique si le canary memoire est deploye.
  bool get hasMemoryCanary => _memoryCanary != null;

  /// Indique si le canary fichier est deploye.
  bool get hasFileCanary => _fileCanary != null;

  /// Indique si le canary config est deploye.
  bool get hasConfigCanary => _configCanary != null;
}
