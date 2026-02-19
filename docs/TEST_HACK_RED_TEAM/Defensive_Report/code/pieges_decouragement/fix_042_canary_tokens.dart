// =============================================================
// FIX-042 : Canary Tokens (fichiers pieges)
// GAP-042: Canary tokens absents (P1)
// Cible: lib/core/security/canary_tokens.dart (nouveau)
// =============================================================
//
// PROBLEME : Impossible de detecter si un attaquant explore le
// systeme de fichiers. Pas de piege ni d'alerte.
//
// SOLUTION :
// 1. Deployer de faux fichiers attractifs pour un attaquant
// 2. Surveiller l'acces (stat.accessed) periodiquement
// 3. Alerter si un fichier piege est lu/modifie
// =============================================================

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Types de canary tokens.
enum CanaryType {
  fakeSSHKey,
  fakeCredentials,
  fakeDatabase,
  fakeEnvFile,
}

/// Etat d'un canary token.
enum CanaryStatus {
  intact,
  accessed,
  modified,
  deleted,
}

/// Enregistrement d'un canary deploye.
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
}

/// Resultat de verification d'un canary.
class CanaryCheckResult {
  final CanaryRecord record;
  final CanaryStatus status;
  final DateTime? lastAccessed;

  const CanaryCheckResult({
    required this.record,
    required this.status,
    this.lastAccessed,
  });
}

/// Callback alerte canary.
typedef CanaryAlertCallback = void Function(CanaryCheckResult result);

/// Gestionnaire de canary tokens.
class CanaryTokenManager {
  final String _registryPath;
  final List<CanaryRecord> _records = [];
  CanaryAlertCallback? onAlert;

  CanaryTokenManager({
    String? registryPath,
    this.onAlert,
  }) : _registryPath = registryPath ??
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/.config/chillapp/.canary_registry';

  /// Deploie tous les canary tokens.
  Future<int> deployAll() async {
    int deployed = 0;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '';

    // 1. Fausse cle SSH backup
    if (await _deployCanary(
      path: '$home/.ssh/id_rsa_backup',
      type: CanaryType.fakeSSHKey,
      content: _generateFakeSSHKey(),
    )) deployed++;

    // 2. Faux fichier credentials
    if (await _deployCanary(
      path: '$home/.config/credentials.json',
      type: CanaryType.fakeCredentials,
      content: _generateFakeCredentials(),
    )) deployed++;

    // 3. Faux fichier .env
    if (await _deployCanary(
      path: '$home/.config/chillapp/.env.production',
      type: CanaryType.fakeEnvFile,
      content: _generateFakeEnv(),
    )) deployed++;

    // 4. Fausse base de donnees
    if (await _deployCanary(
      path: '$home/.local/share/chillapp/secrets.db',
      type: CanaryType.fakeDatabase,
      content: _generateFakeDatabase(),
    )) deployed++;

    // Sauvegarder le registre
    await _saveRegistry();
    return deployed;
  }

  /// Verifie tous les canary tokens deployes.
  Future<List<CanaryCheckResult>> checkAll() async {
    await _loadRegistry();
    final results = <CanaryCheckResult>[];

    for (final record in _records) {
      final result = await _checkCanary(record);
      results.add(result);

      if (result.status != CanaryStatus.intact) {
        onAlert?.call(result);
      }
    }

    return results;
  }

  Future<bool> _deployCanary({
    required String path,
    required CanaryType type,
    required String content,
  }) async {
    try {
      final file = File(path);

      // Ne pas ecraser un vrai fichier !
      if (await file.exists()) return false;

      // Creer le repertoire parent si necessaire
      await file.parent.create(recursive: true);

      // Ecrire le contenu piege
      await file.writeAsString(content);

      // Permissions restrictives (ressemble a un vrai fichier secret)
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

    // Verifier si le contenu a ete modifie
    final content = await file.readAsString();
    final currentHash = sha256.convert(utf8.encode(content)).toString();

    if (currentHash != record.contentHash) {
      return CanaryCheckResult(
        record: record,
        status: CanaryStatus.modified,
        lastAccessed: stat.accessed,
      );
    }

    // Verifier si le fichier a ete lu apres le deploiement
    if (stat.accessed.isAfter(
        record.deployedAt.add(const Duration(seconds: 5)))) {
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

  /// Supprime tous les canary tokens.
  Future<void> removeAll() async {
    await _loadRegistry();
    for (final record in _records) {
      try {
        final file = File(record.path);
        if (await file.exists()) {
          // Zeroiser avant suppression
          final length = await file.length();
          await file.writeAsBytes(List.filled(length, 0));
          await file.delete();
        }
      } catch (_) {}
    }
    _records.clear();
    await _saveRegistry();
  }

  // === Generateurs de contenu piege ===

  String _generateFakeSSHKey() {
    final random = Random.secure();
    final fakeB64 = base64Encode(
      List.generate(270, (_) => random.nextInt(256)),
    );
    return '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB
$fakeB64
CANARY_DO_NOT_USE
-----END OPENSSH PRIVATE KEY-----''';
  }

  String _generateFakeCredentials() {
    return jsonEncode({
      'api_key': 'CANARY_sk_live_${_randomHex(32)}',
      'database_url': 'postgresql://admin:${_randomHex(16)}@db.internal:5432/production',
      'tailscale_auth': 'tskey-auth-${_randomHex(24)}',
      'aws_access_key': 'AKIACANARY${_randomHex(10).toUpperCase()}',
      'aws_secret_key': _randomHex(40),
      '_warning': 'CANARY_TOKEN_FILE',
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
# CANARY_TOKEN_FILE
''';
  }

  String _generateFakeDatabase() {
    return '''SQLite format 3\x00
-- CANARY TOKEN DATABASE --
-- This file is a trap to detect unauthorized access --
CREATE TABLE users (id INTEGER, username TEXT, password_hash TEXT);
INSERT INTO users VALUES (1, 'admin', '${_randomHex(64)}');
INSERT INTO users VALUES (2, 'root', '${_randomHex(64)}');
''';
  }

  String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) =>
      random.nextInt(16).toRadixString(16)).join();
  }

  Future<void> _saveRegistry() async {
    final file = File(_registryPath);
    await file.parent.create(recursive: true);
    final data = _records.map((r) => r.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', _registryPath]);
    }
  }

  Future<void> _loadRegistry() async {
    try {
      final file = File(_registryPath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        _records.clear();
        _records.addAll(data.map((d) =>
          CanaryRecord.fromJson(d as Map<String, dynamic>)));
      }
    } catch (_) {}
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Au premier demarrage de l'app :
//   final canaryManager = CanaryTokenManager(
//     onAlert: (result) {
//       auditLog.log(SecurityAction.canaryTriggered,
//         '${result.record.type.name} ${result.status.name}: ${result.record.path}');
//       // Si un canary est accede, c'est un signe d'intrusion
//       showSecurityAlertDialog('Activite suspecte detectee !');
//     },
//   );
//   await canaryManager.deployAll();
//
// Verification periodique (toutes les 10 minutes) :
//   Timer.periodic(Duration(minutes: 10), (_) async {
//     await canaryManager.checkAll();
//   });
// =============================================================
