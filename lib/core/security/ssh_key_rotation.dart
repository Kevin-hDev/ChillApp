// =============================================================
// FIX-029 : Rotation automatique des cles SSH
// GAP-029 : Absence de rotation des cles SSH (P2)
// Cible  : lib/core/security/ssh_key_rotation.dart (nouveau)
// =============================================================
//
// PROBLEME : Les cles SSH utilisees par ChillApp ne sont jamais
// renouvelees. Une cle comprometee reste valide indefiniment.
//
// SOLUTION :
//   1. Verifier l'age de la cle SSH courante
//   2. Si superieur a maxAgeDays (30 jours par defaut), generer
//      une nouvelle cle avec ssh-keygen
//   3. Deployer la nouvelle cle sur l'hote distant
//   4. Revoquer l'ancienne cle de authorized_keys
//   5. Nettoyer les vieilles sauvegardes (> 90 jours)
//
// SECURITE :
//   - La passphrase est vide (N '') car la cle est protegee par
//     l'acces systeme et Tailscale
//   - Les anciennes cles sont mises a zero avant suppression
//   - Les chemins de fichiers sont echappes contre l'injection shell
// =============================================================

import 'dart:io';

/// Configuration de la rotation des cles SSH.
class KeyRotationConfig {
  /// Age maximal d'une cle avant rotation (jours).
  final int maxAgeDays;

  /// Algorithme de generation de cle ('ed25519' ou 'rsa').
  final String algorithm;

  /// Nombre de bits pour RSA (ignore pour ed25519).
  final int keyBits;

  /// Repertoire SSH (par defaut : ~/.ssh).
  final String sshDir;

  KeyRotationConfig({
    this.maxAgeDays = 30,
    this.algorithm = 'ed25519',
    this.keyBits = 4096,
    String? sshDir,
  }) : sshDir = sshDir ?? _defaultSshDir;

  /// Chemin du repertoire SSH par defaut selon l'OS.
  static String get _defaultSshDir {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      return '$userProfile\\.ssh';
    }
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.ssh';
  }

  /// Expose le repertoire SSH par defaut pour les tests.
  static String get defaultSshDir => _defaultSshDir;
}

/// Resultat de la verification d'age d'une cle SSH.
class RotationCheckResult {
  /// True si la cle doit etre renouvelee.
  final bool needsRotation;

  /// Age de la cle en jours (null si la cle n'existe pas).
  final int? keyAgeDays;

  /// Chemin absolu de la cle SSH verificee.
  final String keyPath;

  /// Raison de la decision (lisible par l'utilisateur).
  final String reason;

  const RotationCheckResult({
    required this.needsRotation,
    required this.keyPath,
    required this.reason,
    this.keyAgeDays,
  });
}

/// Resultat d'une operation de rotation de cle SSH.
class RotationResult {
  /// True si la rotation a reussi.
  final bool success;

  /// Chemin de la nouvelle cle generee (si succes).
  final String? newKeyPath;

  /// Chemin de la sauvegarde de l'ancienne cle (si succes).
  final String? oldKeyBackupPath;

  /// Message d'erreur (si echec).
  final String? error;

  const RotationResult({
    required this.success,
    this.newKeyPath,
    this.oldKeyBackupPath,
    this.error,
  });
}

/// Gestionnaire de rotation des cles SSH de ChillApp.
///
/// CYCLE DE VIE D'UNE ROTATION :
///   1. [checkRotationNeeded]  : detecte si la rotation est necessaire
///   2. [rotateKey]            : genere la nouvelle cle (backup l'ancienne)
///   3. [deployPublicKey]      : copie la cle publique sur l'hote distant
///   4. [revokeOldKey]         : retire l'ancienne cle de authorized_keys
///   5. [cleanupOldKeys]       : supprime les backups de plus de 90 jours
class SshKeyRotation {
  /// Configuration de rotation utilisee.
  final KeyRotationConfig config;

  SshKeyRotation({KeyRotationConfig? config})
      : config = config ?? KeyRotationConfig();

  // ---------------------------------------------------------------------------
  // 1. Verification de l'age
  // ---------------------------------------------------------------------------

  /// Verifie si la cle [keyName] doit etre renouvelee.
  ///
  /// [keyName] : nom de base de la cle (ex: 'id_ed25519').
  /// Retourne [RotationCheckResult] avec l'age et la raison de la decision.
  Future<RotationCheckResult> checkRotationNeeded(String keyName) async {
    final keyPath = '${config.sshDir}/$keyName';
    final keyFile = File(keyPath);

    // La cle n'existe pas : rotation obligatoire
    if (!await keyFile.exists()) {
      return RotationCheckResult(
        needsRotation: true,
        keyPath: keyPath,
        reason: 'Cle SSH introuvable : $keyPath',
      );
    }

    // Calculer l'age en jours
    final stat = await keyFile.stat();
    final ageDays = DateTime.now()
        .difference(stat.modified)
        .inDays;

    if (ageDays >= config.maxAgeDays) {
      return RotationCheckResult(
        needsRotation: true,
        keyPath: keyPath,
        keyAgeDays: ageDays,
        reason:
            'Cle SSH agee de $ageDays jours (limite : ${config.maxAgeDays} jours)',
      );
    }

    return RotationCheckResult(
      needsRotation: false,
      keyPath: keyPath,
      keyAgeDays: ageDays,
      reason: 'Cle SSH valide ($ageDays jours < ${config.maxAgeDays} jours)',
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Generation de la nouvelle cle
  // ---------------------------------------------------------------------------

  /// Genere une nouvelle cle SSH et sauvegarde l'ancienne.
  ///
  /// [keyName]  : nom de base de la cle (ex: 'id_ed25519').
  /// [comment]  : commentaire integre a la cle publique.
  /// Retourne [RotationResult] avec les chemins de la nouvelle cle et backup.
  Future<RotationResult> rotateKey(
    String keyName, {
    String comment = 'chillapp-rotation',
  }) async {
    final keyPath = '${config.sshDir}/$keyName';
    final keyFile = File(keyPath);
    final backupPath = '$keyPath.old';

    try {
      // Sauvegarder l'ancienne cle si elle existe
      if (await keyFile.exists()) {
        final oldContent = await keyFile.readAsBytes();
        await File(backupPath).writeAsBytes(oldContent);
        // Mettre a zero l'ancienne cle avant de la supprimer
        await _zeroFile(keyFile);
        await keyFile.delete();
        // Supprimer aussi l'ancienne pubkey si elle existe
        final oldPubKey = File('$keyPath.pub');
        if (await oldPubKey.exists()) await oldPubKey.delete();
      }

      // Generer la nouvelle cle avec ssh-keygen
      final args = [
        '-t', config.algorithm,
        '-f', keyPath,
        '-N', '', // Passphrase vide (protege par l'acces systeme)
        '-C', comment,
      ];
      if (config.algorithm == 'rsa') {
        args.addAll(['-b', config.keyBits.toString()]);
      }

      final result = await Process.run('ssh-keygen', args);
      if (result.exitCode != 0) {
        return RotationResult(
          success: false,
          error:
              'ssh-keygen a echoue (code ${result.exitCode}): ${result.stderr}',
        );
      }

      return RotationResult(
        success: true,
        newKeyPath: keyPath,
        oldKeyBackupPath: await File(backupPath).exists() ? backupPath : null,
      );
    } catch (e) {
      return RotationResult(
        success: false,
        error: 'Erreur lors de la rotation: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Deploiement de la cle publique
  // ---------------------------------------------------------------------------

  /// Deploie la cle publique [keyName].pub sur [host] pour [user].
  ///
  /// Utilise `ssh` avec la cle privee temporaire pour eviter tout
  /// mot de passe interactif.
  Future<RotationResult> deployPublicKey(
    String keyName,
    String user,
    String host, {
    int port = 22,
    String? identityFile,
  }) async {
    final pubKeyPath = '${config.sshDir}/$keyName.pub';
    final pubKeyFile = File(pubKeyPath);

    if (!await pubKeyFile.exists()) {
      return const RotationResult(
        success: false,
        error: 'Cle publique introuvable',
      );
    }

    try {
      final pubKeyContent = (await pubKeyFile.readAsString()).trim();
      // Echapper pour une utilisation dans une commande shell distante
      final escapedKey = shellEscape(pubKeyContent);

      final sshArgs = [
        '-o', 'StrictHostKeyChecking=accept-new',
        '-p', port.toString(),
        if (identityFile != null) ...['-i', identityFile],
        '$user@$host',
        'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
            "grep -qF '$escapedKey' ~/.ssh/authorized_keys 2>/dev/null || "
            "echo '$escapedKey' >> ~/.ssh/authorized_keys && "
            'chmod 600 ~/.ssh/authorized_keys',
      ];

      final result = await Process.run('ssh', sshArgs);
      if (result.exitCode != 0) {
        return RotationResult(
          success: false,
          error: 'Deploiement SSH echoue: ${result.stderr}',
        );
      }
      return const RotationResult(success: true);
    } catch (e) {
      return RotationResult(
        success: false,
        error: 'Erreur de deploiement: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Revocation de l'ancienne cle
  // ---------------------------------------------------------------------------

  /// Retire [oldPublicKey] du fichier authorized_keys de [user]@[host].
  ///
  /// Utilise `grep -v -F` pour supprimer la ligne contenant la cle
  /// (correspondance litterale, pas de regex — evite l'injection).
  Future<RotationResult> revokeOldKey(
    String oldPublicKey,
    String user,
    String host, {
    int port = 22,
    String? identityFile,
  }) async {
    try {
      final sshArgs = [
        '-o', 'StrictHostKeyChecking=accept-new',
        '-p', port.toString(),
        if (identityFile != null) ...['-i', identityFile],
        '$user@$host',
        "grep -v -F '${oldPublicKey.replaceAll("'", "'\\''")}' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && "
            'mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && '
            'chmod 600 ~/.ssh/authorized_keys',
      ];

      final result = await Process.run('ssh', sshArgs);
      if (result.exitCode != 0) {
        return RotationResult(
          success: false,
          error: 'Revocation echouee: ${result.stderr}',
        );
      }
      return const RotationResult(success: true);
    } catch (e) {
      return RotationResult(
        success: false,
        error: 'Erreur de revocation: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 5. Nettoyage des vieux backups
  // ---------------------------------------------------------------------------

  /// Supprime les fichiers de sauvegarde (.old) ages de plus de 90 jours.
  ///
  /// Met les fichiers a zero avant suppression pour eviter la recuperation.
  Future<int> cleanupOldKeys({int olderThanDays = 90}) async {
    var deleted = 0;
    final sshDirectory = Directory(config.sshDir);
    if (!await sshDirectory.exists()) return 0;

    await for (final entity in sshDirectory.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.old')) continue;

      try {
        final stat = await entity.stat();
        final ageDays =
            DateTime.now().difference(stat.modified).inDays;
        if (ageDays >= olderThanDays) {
          await _zeroFile(entity);
          await entity.delete();
          deleted++;
        }
      } catch (_) {
        // Fichier verrouille ou supprime entre temps — ignorer
      }
    }
    return deleted;
  }

  // ---------------------------------------------------------------------------
  // Utilitaires publics
  // ---------------------------------------------------------------------------

  /// Echappe une chaine pour une utilisation dans un argument shell single-quote.
  ///
  /// Methode publique et statique pour faciliter les tests.
  /// Technique : termine le single-quote, insere un `\'` escape, rouvre.
  static String shellEscape(String value) {
    return value.replaceAll("'", "'\\''");
  }

  // ---------------------------------------------------------------------------
  // Utilitaires prives
  // ---------------------------------------------------------------------------

  /// Ecrase le contenu d'un fichier avec des zeros avant suppression.
  ///
  /// Evite la recuperation de cles privees sur disque.
  Future<void> _zeroFile(File file) async {
    try {
      final length = await file.length();
      if (length > 0) {
        final zeros = List<int>.filled(length, 0);
        await file.writeAsBytes(zeros, flush: true);
      }
    } catch (_) {
      // Si la mise a zero echoue, continuer quand meme
    }
  }
}
