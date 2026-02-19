// =============================================================
// FIX-029 : Rotation automatique des cles SSH
// GAP-029: Rotation automatique des cles SSH absente (P2)
// Cible: lib/core/security/ssh_key_rotation.dart (nouveau)
// =============================================================
//
// PROBLEME : Les cles SSH sont statiques. En cas de compromission,
// l'acces reste ouvert indefiniment.
//
// SOLUTION :
// 1. Verification de l'age de la cle au demarrage
// 2. Generation d'une nouvelle paire ed25519 si > 30 jours
// 3. Deploiement automatique de la cle publique via SSH
// 4. Revocation de l'ancienne cle dans authorized_keys
// 5. Journal des rotations
// =============================================================

import 'dart:io';
import 'dart:convert';

/// Configuration de rotation des cles SSH.
class KeyRotationConfig {
  /// Duree de vie maximale d'une cle en jours.
  final int maxAgeDays;

  /// Algorithme de generation (ed25519 recommande).
  final String algorithm;

  /// Taille de cle (pour RSA uniquement, ignore pour ed25519).
  final int keyBits;

  /// Chemin du dossier SSH.
  final String sshDir;

  const KeyRotationConfig({
    this.maxAgeDays = 30,
    this.algorithm = 'ed25519',
    this.keyBits = 4096,
    String? sshDir,
  }) : sshDir = sshDir ?? _defaultSshDir;

  static String get _defaultSshDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return '$home/.ssh';
  }
}

/// Resultat d'une verification de rotation.
class RotationCheckResult {
  final bool needsRotation;
  final int keyAgeDays;
  final String keyPath;
  final String? reason;

  const RotationCheckResult({
    required this.needsRotation,
    required this.keyAgeDays,
    required this.keyPath,
    this.reason,
  });
}

/// Resultat d'une rotation.
class RotationResult {
  final bool success;
  final String? newKeyPath;
  final String? oldKeyBackupPath;
  final String? error;

  const RotationResult({
    required this.success,
    this.newKeyPath,
    this.oldKeyBackupPath,
    this.error,
  });
}

/// Gestionnaire de rotation automatique des cles SSH.
class SshKeyRotation {
  final KeyRotationConfig config;

  SshKeyRotation({KeyRotationConfig? config})
      : config = config ?? const KeyRotationConfig();

  /// Verifie si une rotation est necessaire.
  Future<RotationCheckResult> checkRotationNeeded({
    String keyName = 'id_ed25519',
  }) async {
    final keyPath = '${config.sshDir}/$keyName';
    final keyFile = File(keyPath);

    if (!await keyFile.exists()) {
      return RotationCheckResult(
        needsRotation: true,
        keyAgeDays: -1,
        keyPath: keyPath,
        reason: 'Cle inexistante',
      );
    }

    final stat = await keyFile.stat();
    final age = DateTime.now().difference(stat.modified);
    final ageDays = age.inDays;

    if (ageDays >= config.maxAgeDays) {
      return RotationCheckResult(
        needsRotation: true,
        keyAgeDays: ageDays,
        keyPath: keyPath,
        reason: 'Cle de $ageDays jours (max ${config.maxAgeDays})',
      );
    }

    return RotationCheckResult(
      needsRotation: false,
      keyAgeDays: ageDays,
      keyPath: keyPath,
    );
  }

  /// Genere une nouvelle paire de cles ed25519.
  /// Renomme l'ancienne cle en .old.{timestamp}.
  Future<RotationResult> rotateKey({
    String keyName = 'id_ed25519',
    String comment = 'chillapp-rotated',
  }) async {
    final keyPath = '${config.sshDir}/$keyName';
    final keyFile = File(keyPath);
    String? backupPath;

    try {
      // 1. Sauvegarder l'ancienne cle si elle existe
      if (await keyFile.exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        backupPath = '$keyPath.old.$timestamp';
        await keyFile.rename(backupPath);

        // Sauvegarder aussi la cle publique
        final pubFile = File('$keyPath.pub');
        if (await pubFile.exists()) {
          await pubFile.rename('$backupPath.pub');
        }
      }

      // 2. Generer la nouvelle cle
      final result = await Process.run('ssh-keygen', [
        '-t', config.algorithm,
        '-f', keyPath,
        '-N', '', // Pas de passphrase (protege par le PIN de l'app)
        '-C', '$comment-${DateTime.now().toIso8601String()}',
        if (config.algorithm == 'rsa') ...['-b', '${config.keyBits}'],
      ]);

      if (result.exitCode != 0) {
        // Restaurer l'ancienne cle en cas d'echec
        if (backupPath != null) {
          await File(backupPath).rename(keyPath);
          final backupPub = File('$backupPath.pub');
          if (await backupPub.exists()) {
            await backupPub.rename('$keyPath.pub');
          }
        }
        return RotationResult(
          success: false,
          error: 'ssh-keygen echoue: ${result.stderr}',
        );
      }

      // 3. Fixer les permissions
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', keyPath]);
        await Process.run('chmod', ['644', '$keyPath.pub']);
      }

      // 4. Logger la rotation
      await _logRotation(keyPath, backupPath);

      return RotationResult(
        success: true,
        newKeyPath: keyPath,
        oldKeyBackupPath: backupPath,
      );
    } catch (e) {
      return RotationResult(
        success: false,
        error: 'Exception: $e',
      );
    }
  }

  /// Deploie la cle publique sur un hote distant via SSH.
  /// Utilise ssh-copy-id ou equivalent.
  Future<bool> deployPublicKey({
    required String host,
    required String user,
    String keyName = 'id_ed25519',
    int port = 22,
  }) async {
    final pubKeyPath = '${config.sshDir}/$keyName.pub';
    final pubKeyFile = File(pubKeyPath);

    if (!await pubKeyFile.exists()) return false;

    final pubKey = (await pubKeyFile.readAsString()).trim();

    // Utiliser ssh pour ajouter la cle (plus fiable que ssh-copy-id)
    final result = await Process.run('ssh', [
      '-p', '$port',
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ConnectTimeout=10',
      '$user@$host',
      'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
          'echo ${_shellEscape(pubKey)} >> ~/.ssh/authorized_keys && '
          'chmod 600 ~/.ssh/authorized_keys',
    ]);

    return result.exitCode == 0;
  }

  /// Revoque une ancienne cle publique sur un hote distant.
  Future<bool> revokeOldKey({
    required String host,
    required String user,
    required String oldPubKeyPath,
    int port = 22,
  }) async {
    final oldPubFile = File(oldPubKeyPath);
    if (!await oldPubFile.exists()) return true; // Rien a revoquer

    final oldPubKey = (await oldPubFile.readAsString()).trim();
    // Extraire juste la partie cle (sans commentaire)
    final keyParts = oldPubKey.split(' ');
    if (keyParts.length < 2) return false;
    final keyFingerprint = keyParts[1]; // La partie base64

    // Supprimer la ligne contenant cette cle
    final result = await Process.run('ssh', [
      '-p', '$port',
      '-o', 'ConnectTimeout=10',
      '$user@$host',
      'sed -i "/${_shellEscape(keyFingerprint)}/d" ~/.ssh/authorized_keys',
    ]);

    return result.exitCode == 0;
  }

  /// Nettoie les anciennes cles de sauvegarde (> 90 jours).
  Future<int> cleanupOldKeys() async {
    final dir = Directory(config.sshDir);
    if (!await dir.exists()) return 0;

    int cleaned = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 90));

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.contains('.old.')) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          // Zeroiser avant suppression
          final length = await entity.length();
          await entity.writeAsBytes(List.filled(length, 0));
          await entity.delete();
          cleaned++;
        }
      }
    }

    return cleaned;
  }

  /// Echappe une chaine pour utilisation dans un shell.
  String _shellEscape(String s) {
    return s.replaceAll("'", "'\\''");
  }

  /// Journalise une rotation.
  Future<void> _logRotation(String newPath, String? oldPath) async {
    final logFile = File('${config.sshDir}/.key_rotation_log');
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'rotate',
      'new_key': newPath,
      'old_key_backup': oldPath,
      'algorithm': config.algorithm,
    };
    await logFile.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
    // Permissions restrictives
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', logFile.path]);
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Dans main.dart ou app.dart, au demarrage :
//
//   final rotation = SshKeyRotation();
//   final check = await rotation.checkRotationNeeded();
//   if (check.needsRotation) {
//     // Afficher un dialog a l'utilisateur
//     final confirmed = await showRotationDialog(check);
//     if (confirmed) {
//       final result = await rotation.rotateKey();
//       if (result.success) {
//         // Deployer sur les hotes configures
//         await rotation.deployPublicKey(host: '...', user: '...');
//         // Revoquer l'ancienne cle
//         if (result.oldKeyBackupPath != null) {
//           await rotation.revokeOldKey(
//             host: '...', user: '...',
//             oldPubKeyPath: '${result.oldKeyBackupPath}.pub',
//           );
//         }
//       }
//     }
//   }
//
// Nettoyage periodique :
//   await rotation.cleanupOldKeys(); // Supprimer les .old > 90 jours
// =============================================================
