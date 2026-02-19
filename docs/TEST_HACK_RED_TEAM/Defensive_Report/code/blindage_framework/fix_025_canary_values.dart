// =============================================================
// FIX-025 : Canary values et tripwires
// GAP-025: Canary values et tripwires absents
// Cible: lib/core/security/canary_values.dart (nouveau)
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

/// Canary en memoire : valeur sentinelle qui detecte la corruption.
class MemoryCanary {
  /// Valeur canary generee au demarrage.
  final Uint8List _canaryValue;

  /// Hash attendu du canary.
  final String _expectedHash;

  MemoryCanary._({
    required Uint8List canaryValue,
    required String expectedHash,
  })  : _canaryValue = canaryValue,
        _expectedHash = expectedHash;

  /// Cree un nouveau canary avec une valeur aleatoire.
  factory MemoryCanary.create() {
    final rng = Random.secure();
    final value = Uint8List.fromList(
      List.generate(64, (_) => rng.nextInt(256)),
    );
    final hash = sha256.convert(value).toString();
    return MemoryCanary._(canaryValue: value, expectedHash: hash);
  }

  /// Verifie que le canary n'a pas ete modifie.
  /// Retourne false si corruption detectee.
  bool verify() {
    final currentHash = sha256.convert(_canaryValue).toString();
    // Comparaison en temps constant
    if (currentHash.length != _expectedHash.length) return false;
    int result = 0;
    for (int i = 0; i < currentHash.length; i++) {
      result |= currentHash.codeUnitAt(i) ^ _expectedHash.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Canary fichier : detecte les acces non autorises au disque.
class FileCanary {
  final String _canaryPath;
  final String _expectedContent;
  final String _expectedHash;

  FileCanary._({
    required String canaryPath,
    required String expectedContent,
    required String expectedHash,
  })  : _canaryPath = canaryPath,
        _expectedContent = expectedContent,
        _expectedHash = expectedHash;

  /// Cree un fichier canary sur disque.
  /// Le fichier contient des donnees factices qui semblent
  /// interessantes pour un attaquant.
  static Future<FileCanary> deploy({
    required String directory,
    String filename = '.cache_config.dat',
  }) async {
    final canaryPath = '$directory/$filename';

    // Contenu qui attire un attaquant
    final content = jsonEncode({
      'api_key': _generateFakeToken(),
      'db_password': _generateFakeToken(),
      'admin_token': _generateFakeToken(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final hash = sha256.convert(utf8.encode(content)).toString();

    // Ecrire le fichier
    final file = File(canaryPath);
    await file.writeAsString(content);

    // Permissions restrictives
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', canaryPath]);
    }

    return FileCanary._(
      canaryPath: canaryPath,
      expectedContent: content,
      expectedHash: hash,
    );
  }

  /// Verifie si le fichier canary a ete lu ou modifie.
  Future<CanaryStatus> check() async {
    final file = File(_canaryPath);

    if (!await file.exists()) {
      return CanaryStatus.deleted; // Quelqu'un l'a supprime
    }

    final content = await file.readAsString();
    final hash = sha256.convert(utf8.encode(content)).toString();

    if (hash != _expectedHash) {
      return CanaryStatus.modified; // Quelqu'un l'a modifie
    }

    // Verifier la date d'acces (Linux/macOS)
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final stat = await file.stat();
        // Si accessed est recent alors que personne ne devrait lire ce fichier
        final accessAge = DateTime.now().difference(stat.accessed);
        if (accessAge.inSeconds < 60) {
          return CanaryStatus.accessed; // Lu recemment
        }
      } catch (_) {}
    }

    return CanaryStatus.intact;
  }

  /// Genere un faux token qui semble reel.
  static String _generateFakeToken() {
    final rng = Random.secure();
    final bytes = List.generate(24, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }
}

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

/// Checksum de la configuration pour detecter le tampering.
class ConfigCanary {
  final Map<String, String> _checksums;

  ConfigCanary._(this._checksums);

  /// Calcule les checksums de tous les fichiers de config.
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

  /// Verifie si les fichiers de config ont ete modifies.
  /// Retourne la liste des fichiers modifies.
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

/// Gestionnaire global des canaries.
class CanaryManager {
  MemoryCanary? _memoryCanary;
  FileCanary? _fileCanary;
  ConfigCanary? _configCanary;

  /// Callback invoque quand un canary est declenche.
  final void Function(String type, CanaryStatus status)? onTriggered;

  CanaryManager({this.onTriggered});

  /// Deploie tous les canaries.
  Future<void> deployAll({
    required String appDataDir,
    required List<String> configPaths,
  }) async {
    // 1. Canary memoire
    _memoryCanary = MemoryCanary.create();

    // 2. Canary fichier
    _fileCanary = await FileCanary.deploy(directory: appDataDir);

    // 3. Checksums config
    _configCanary = await ConfigCanary.snapshot(configPaths: configPaths);
  }

  /// Verifie tous les canaries.
  /// Retourne true si tout est intact.
  Future<bool> verifyAll() async {
    bool allOk = true;

    // Memoire
    if (_memoryCanary != null && !_memoryCanary!.verify()) {
      onTriggered?.call('memory', CanaryStatus.modified);
      allOk = false;
    }

    // Fichier
    if (_fileCanary != null) {
      final status = await _fileCanary!.check();
      if (status != CanaryStatus.intact) {
        onTriggered?.call('file', status);
        allOk = false;
      }
    }

    // Config
    if (_configCanary != null) {
      final modified = await _configCanary!.verify();
      if (modified.isNotEmpty) {
        onTriggered?.call('config', CanaryStatus.modified);
        allOk = false;
      }
    }

    return allOk;
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Creer lib/core/security/canary_values.dart
//
// 2. Dans main.dart, deployer les canaries :
//    final canaryManager = CanaryManager(
//      onTriggered: (type, status) {
//        auditLog.log(SecurityAction.canaryTriggered,
//          detail: '$type: ${status.name}');
//        // Envoyer une alerte
//      },
//    );
//    await canaryManager.deployAll(
//      appDataDir: appDataPath,
//      configPaths: [
//        '$appDataPath/shared_preferences.json',
//        '$appDataPath/chillapp.conf',
//      ],
//    );
//
// 3. Verification periodique (toutes les 5 minutes) :
//    Timer.periodic(Duration(minutes: 5), (_) async {
//      await canaryManager.verifyAll();
//    });
// =============================================================
