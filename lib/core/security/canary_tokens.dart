// FIX-042 : Canary Tokens (fichiers pieges)
// GAP-042: Canary tokens absents (P1)
// Deploie de faux fichiers attractifs et detecte leur acces non autorise.

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Types de canary tokens disponibles.
enum CanaryType {
  fakeSSHKey,
  fakeCredentials,
  fakeDatabase,
  fakeEnvFile,
}

/// Etat d'un canary token apres verification.
enum CanaryStatus {
  /// Le fichier n'a pas ete touche.
  intact,

  /// Le fichier a ete lu apres le deploiement.
  accessed,

  /// Le contenu du fichier a ete modifie.
  modified,

  /// Le fichier a ete supprime.
  deleted,
}

/// Enregistrement persistant d'un canary deploye.
class CanaryRecord {
  final String path;
  final CanaryType type;
  final DateTime deployedAt;
  final String contentHash;

  const CanaryRecord({
    required this.path,
    required this.type,
    required this.deployedAt,
    required this.contentHash,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'type': type.name,
        'deployed_at': deployedAt.toIso8601String(),
        'content_hash': contentHash,
      };

  factory CanaryRecord.fromJson(Map<String, dynamic> json) {
    return CanaryRecord(
      path: json['path'] as String,
      type: CanaryType.values.firstWhere((t) => t.name == json['type']),
      deployedAt: DateTime.parse(json['deployed_at'] as String),
      contentHash: json['content_hash'] as String,
    );
  }

  @override
  String toString() => 'CanaryRecord(${type.name} @ $path)';
}

/// Resultat de verification d'un canary token.
class CanaryCheckResult {
  final CanaryRecord record;
  final CanaryStatus status;
  final DateTime? lastAccessed;

  const CanaryCheckResult({
    required this.record,
    required this.status,
    this.lastAccessed,
  });

  /// Vrai si le canary a ete compromis (accede, modifie ou supprime).
  bool get isTriggered => status != CanaryStatus.intact;

  @override
  String toString() =>
      'CanaryCheckResult(${record.type.name} → ${status.name})';
}

/// Callback d'alerte quand un canary est compromis.
typedef CanaryAlertCallback = void Function(CanaryCheckResult result);

/// Gestionnaire de canary tokens.
///
/// Deploie des fichiers pieges realistes (cles SSH, credentials, .env,
/// base de donnees) et surveille leur integrite. Toute lecture ou
/// modification d'un canary est un signe fort d'intrusion.
class CanaryTokenManager {
  final String _registryPath;
  final List<CanaryRecord> _records = [];

  /// Appelee quand un canary est compromis.
  CanaryAlertCallback? onAlert;

  /// Delai de grace apres deploiement avant de detecter un acces (secondes).
  static const int _accessGraceSeconds = 5;

  CanaryTokenManager({
    String? registryPath,
    this.onAlert,
  }) : _registryPath = registryPath ??
            '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''}/.config/chillapp/.canary_registry';

  /// Liste des canary actuellement suivis (lecture seule).
  List<CanaryRecord> get records => List.unmodifiable(_records);

  // ---------------------------------------------------------------------------
  // Deploiement
  // ---------------------------------------------------------------------------

  /// Deploie tous les canary tokens. Retourne le nombre de canaries crees.
  Future<int> deployAll() async {
    int deployed = 0;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';

    final targets = [
      (
        path: '$home/.ssh/id_rsa_backup',
        type: CanaryType.fakeSSHKey,
        content: _generateFakeSSHKey(),
      ),
      (
        path: '$home/.config/credentials.json',
        type: CanaryType.fakeCredentials,
        content: _generateFakeCredentials(),
      ),
      (
        path: '$home/.config/chillapp/.env.production',
        type: CanaryType.fakeEnvFile,
        content: _generateFakeEnv(),
      ),
      (
        path: '$home/.local/share/chillapp/secrets.db',
        type: CanaryType.fakeDatabase,
        content: _generateFakeDatabase(),
      ),
    ];

    for (final t in targets) {
      if (await _deployCanary(path: t.path, type: t.type, content: t.content)) {
        deployed++;
      }
    }

    await _saveRegistry();
    return deployed;
  }

  /// Deploie un seul canary. Retourne true si le deploiement a reussi.
  Future<bool> deployOne({
    required String path,
    required CanaryType type,
    required String content,
  }) async {
    final ok = await _deployCanary(path: path, type: type, content: content);
    if (ok) await _saveRegistry();
    return ok;
  }

  // ---------------------------------------------------------------------------
  // Verification
  // ---------------------------------------------------------------------------

  /// Verifie tous les canary tokens deployes. Appelle [onAlert] si compromis.
  Future<List<CanaryCheckResult>> checkAll() async {
    await _loadRegistry();
    final results = <CanaryCheckResult>[];

    for (final record in _records) {
      final result = await _checkCanary(record);
      results.add(result);
      if (result.isTriggered) {
        onAlert?.call(result);
      }
    }

    return results;
  }

  /// Verifie un seul canary par son chemin.
  Future<CanaryCheckResult?> checkOne(String path) async {
    await _loadRegistry();
    final record = _records.where((r) => r.path == path).firstOrNull;
    if (record == null) return null;
    final result = await _checkCanary(record);
    if (result.isTriggered) onAlert?.call(result);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Suppression securisee
  // ---------------------------------------------------------------------------

  /// Supprime tous les canary tokens (zero-fill avant suppression).
  Future<void> removeAll() async {
    await _loadRegistry();
    for (final record in _records) {
      try {
        final file = File(record.path);
        if (await file.exists()) {
          // Zeroiser le contenu avant suppression.
          final length = await file.length();
          await file.writeAsBytes(List.filled(length, 0));
          await file.delete();
        }
      } catch (_) {}
    }
    _records.clear();
    await _saveRegistry();
  }

  // ---------------------------------------------------------------------------
  // Implementation interne
  // ---------------------------------------------------------------------------

  Future<bool> _deployCanary({
    required String path,
    required CanaryType type,
    required String content,
  }) async {
    try {
      final file = File(path);

      // Ne jamais ecraser un vrai fichier existant.
      if (await file.exists()) return false;

      // Creer les repertoires parents si necessaire.
      await file.parent.create(recursive: true);
      await file.writeAsString(content);

      // Permissions restrictives (ressemble a un vrai fichier secret).
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', path]);
      }

      final hash = sha256.convert(utf8.encode(content)).toString();
      _records.add(CanaryRecord(
        path: path,
        type: type,
        deployedAt: DateTime.now(),
        contentHash: hash,
      ));

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<CanaryCheckResult> _checkCanary(CanaryRecord record) async {
    final file = File(record.path);

    if (!await file.exists()) {
      return CanaryCheckResult(
        record: record,
        status: CanaryStatus.deleted,
      );
    }

    final stat = await file.stat();

    // Verifier l'integrite du contenu.
    final content = await file.readAsString();
    final currentHash = sha256.convert(utf8.encode(content)).toString();

    if (currentHash != record.contentHash) {
      return CanaryCheckResult(
        record: record,
        status: CanaryStatus.modified,
        lastAccessed: stat.accessed,
      );
    }

    // Verifier si le fichier a ete lu apres le deploiement + grace.
    final graceEnd =
        record.deployedAt.add(Duration(seconds: _accessGraceSeconds));
    if (stat.accessed.isAfter(graceEnd)) {
      return CanaryCheckResult(
        record: record,
        status: CanaryStatus.accessed,
        lastAccessed: stat.accessed,
      );
    }

    return CanaryCheckResult(
      record: record,
      status: CanaryStatus.intact,
      lastAccessed: stat.accessed,
    );
  }

  // ---------------------------------------------------------------------------
  // Generateurs de contenu piege
  // ---------------------------------------------------------------------------

  String _generateFakeSSHKey() {
    final random = Random.secure();
    final fakeB64 = base64Encode(
      List.generate(270, (_) => random.nextInt(256)),
    );
    return '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB
$fakeB64
-----END OPENSSH PRIVATE KEY-----''';
  }

  String _generateFakeCredentials() {
    return jsonEncode({
      'api_key': 'CANARY_sk_live_${_randomHex(32)}',
      'database_url':
          'postgresql://admin:${_randomHex(16)}@db.internal:5432/production',
      'tailscale_auth': 'tskey-auth-${_randomHex(24)}',
      'aws_access_key': 'AKIACANARY${_randomHex(10).toUpperCase()}',
      'aws_secret_key': _randomHex(40),
      '_internal_ref': _randomHex(8),
    });
  }

  String _generateFakeEnv() {
    return '''# ChillApp Production Environment
DATABASE_URL=postgresql://admin:${_randomHex(16)}@10.0.1.50:5432/chillapp
REDIS_URL=redis://:${_randomHex(16)}@10.0.1.51:6379
JWT_SECRET=${_randomHex(64)}
TAILSCALE_AUTH_KEY=tskey-auth-${_randomHex(24)}
SSH_PRIVATE_KEY_PATH=/root/.ssh/production_key
ADMIN_PASSWORD=${_randomHex(20)}
# Generated ${DateTime.now().millisecondsSinceEpoch}
''';
  }

  String _generateFakeDatabase() {
    return '''SQLite format 3\x00
-- ChillApp internal store --
CREATE TABLE users (id INTEGER, username TEXT, password_hash TEXT);
INSERT INTO users VALUES (1, 'admin', '${_randomHex(64)}');
INSERT INTO users VALUES (2, 'root', '${_randomHex(64)}');
''';
  }

  String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }

  // ---------------------------------------------------------------------------
  // Persistance du registre
  // ---------------------------------------------------------------------------

  Future<void> _saveRegistry() async {
    try {
      final file = File(_registryPath);
      await file.parent.create(recursive: true);
      final data = _records.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', _registryPath]);
      }
    } catch (_) {}
  }

  Future<void> _loadRegistry() async {
    try {
      final file = File(_registryPath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        _records.clear();
        _records.addAll(
            data.map((d) => CanaryRecord.fromJson(d as Map<String, dynamic>)));
      }
    } catch (_) {}
  }
}
