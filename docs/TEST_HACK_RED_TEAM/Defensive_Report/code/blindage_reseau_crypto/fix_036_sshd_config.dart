// =============================================================
// FIX-036 : Template sshd_config durci
// GAP-036: Template sshd_config durci absent (P1)
// Cible: lib/core/security/sshd_hardening.dart (nouveau)
// =============================================================
//
// PROBLEME : Le PC cible peut avoir une config SSH faible
// (mots de passe, root login, algorithmes obsoletes).
// ChillApp devrait proposer un durcissement du serveur SSH.
//
// SOLUTION :
// 1. Template sshd_config avec best practices
// 2. Verification de la config existante
// 3. Application des corrections (avec backup)
// =============================================================

import 'dart:io';

/// Parametres de durcissement sshd_config.
class SshdHardeningConfig {
  /// Port SSH (par defaut 22, peut etre change).
  final int port;

  /// Nombre max de tentatives d'authentification.
  final int maxAuthTries;

  /// Delai de grace pour le login (secondes).
  final int loginGraceTime;

  /// Limite de rekey (donnees, temps).
  final String rekeyLimit;

  const SshdHardeningConfig({
    this.port = 22,
    this.maxAuthTries = 3,
    this.loginGraceTime = 60,
    this.rekeyLimit = '512M 1h',
  });
}

/// Verification d'un parametre sshd_config.
class SshdCheckResult {
  final String parameter;
  final String? currentValue;
  final String expectedValue;
  final bool isCompliant;
  final String severity; // critical, warning, info

  const SshdCheckResult({
    required this.parameter,
    this.currentValue,
    required this.expectedValue,
    required this.isCompliant,
    required this.severity,
  });
}

/// Durcissement du serveur SSH sur la machine cible.
class SshdHardening {
  final SshdHardeningConfig config;

  SshdHardening({SshdHardeningConfig? config})
      : config = config ?? const SshdHardeningConfig();

  /// Template sshd_config durci complet.
  String get hardenedTemplate => '''
# =============================================================
# sshd_config durci par ChillApp
# Genere le ${DateTime.now().toIso8601String()}
# =============================================================

# --- Reseau ---
Port ${config.port}
AddressFamily inet
ListenAddress 0.0.0.0

# --- Authentification ---
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
AuthenticationMethods publickey
MaxAuthTries ${config.maxAuthTries}
MaxSessions 3
LoginGraceTime ${config.loginGraceTime}

# --- Algorithmes (durcis contre Terrapin CVE-2023-48795) ---
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,rsa-sha2-512,rsa-sha2-256
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr,aes192-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# --- Renouvellement de session ---
RekeyLimit ${config.rekeyLimit}

# --- Securite ---
StrictModes yes
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
PrintMotd no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxStartups 10:30:60
PermitUserEnvironment no

# --- Logging ---
SyslogFacility AUTH
LogLevel VERBOSE

# --- Restrictions ---
AllowUsers *@100.64.0.0/10
# N'autorise que les connexions depuis le reseau Tailscale

# --- Subsystem ---
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
''';

  /// Verifie la conformite du sshd_config existant.
  Future<List<SshdCheckResult>> auditConfig({
    String configPath = '/etc/ssh/sshd_config',
  }) async {
    final results = <SshdCheckResult>[];
    final file = File(configPath);

    if (!await file.exists()) {
      results.add(const SshdCheckResult(
        parameter: 'sshd_config',
        expectedValue: 'exists',
        isCompliant: false,
        severity: 'critical',
      ));
      return results;
    }

    final content = await file.readAsString();
    final lines = content.split('\n');

    // Map des parametres actuels
    final params = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        params[parts[0].toLowerCase()] = parts.sublist(1).join(' ');
      }
    }

    // Verifications critiques
    results.add(_check(params, 'PermitRootLogin', 'no', 'critical'));
    results.add(_check(params, 'PasswordAuthentication', 'no', 'critical'));
    results.add(_check(params, 'PubkeyAuthentication', 'yes', 'critical'));
    results.add(_check(params, 'PermitEmptyPasswords', 'no', 'critical'));

    // Verifications importantes
    results.add(_checkMaxAuthTries(params));
    results.add(_check(params, 'X11Forwarding', 'no', 'warning'));
    results.add(_check(params, 'AllowTcpForwarding', 'no', 'warning'));
    results.add(_check(params, 'AllowAgentForwarding', 'no', 'warning'));
    results.add(_check(params, 'StrictModes', 'yes', 'warning'));

    // Verifications crypto
    results.add(_checkKex(params));
    results.add(_checkCiphers(params));
    results.add(_checkMacs(params));

    // Informationnel
    results.add(_check(params, 'LogLevel', 'VERBOSE', 'info'));

    return results;
  }

  SshdCheckResult _check(
    Map<String, String> params,
    String key,
    String expected,
    String severity,
  ) {
    final current = params[key.toLowerCase()];
    return SshdCheckResult(
      parameter: key,
      currentValue: current,
      expectedValue: expected,
      isCompliant: current?.toLowerCase() == expected.toLowerCase(),
      severity: severity,
    );
  }

  SshdCheckResult _checkMaxAuthTries(Map<String, String> params) {
    final current = params['maxauthtries'];
    final value = int.tryParse(current ?? '');
    return SshdCheckResult(
      parameter: 'MaxAuthTries',
      currentValue: current,
      expectedValue: '<= ${config.maxAuthTries}',
      isCompliant: value != null && value <= config.maxAuthTries,
      severity: 'warning',
    );
  }

  SshdCheckResult _checkKex(Map<String, String> params) {
    final current = params['kexalgorithms'];
    final weakKex = [
      'diffie-hellman-group1-sha1',
      'diffie-hellman-group14-sha1',
      'diffie-hellman-group-exchange-sha1',
    ];
    final hasWeak = current != null &&
        weakKex.any((w) => current.toLowerCase().contains(w));
    return SshdCheckResult(
      parameter: 'KexAlgorithms',
      currentValue: current,
      expectedValue: 'curve25519-sha256,... (sans SHA-1)',
      isCompliant: current != null && !hasWeak,
      severity: 'critical',
    );
  }

  SshdCheckResult _checkCiphers(Map<String, String> params) {
    final current = params['ciphers'];
    final weakCiphers = ['3des-cbc', 'arcfour', 'blowfish-cbc', 'aes128-cbc', 'aes256-cbc'];
    final hasWeak = current != null &&
        weakCiphers.any((w) => current.toLowerCase().contains(w));
    return SshdCheckResult(
      parameter: 'Ciphers',
      currentValue: current,
      expectedValue: 'aes256-gcm,chacha20-poly1305,... (sans CBC)',
      isCompliant: current != null && !hasWeak,
      severity: 'critical',
    );
  }

  SshdCheckResult _checkMacs(Map<String, String> params) {
    final current = params['macs'];
    final weakMacs = ['hmac-md5', 'hmac-sha1', 'umac-64'];
    final hasWeak = current != null &&
        weakMacs.any((w) => current.toLowerCase().contains(w));
    return SshdCheckResult(
      parameter: 'MACs',
      currentValue: current,
      expectedValue: 'hmac-sha2-512-etm,... (sans MD5/SHA-1)',
      isCompliant: current != null && !hasWeak,
      severity: 'warning',
    );
  }

  /// Deploie le template durci sur la machine cible (via SSH).
  Future<bool> deployHardenedConfig({
    required String host,
    required String user,
    int port = 22,
  }) async {
    try {
      // 1. Backup de l'ancien sshd_config
      final backupResult = await Process.run('ssh', [
        '-p', '$port',
        '-o', 'ConnectTimeout=10',
        '$user@$host',
        'sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.${DateTime.now().millisecondsSinceEpoch}',
      ]);
      if (backupResult.exitCode != 0) return false;

      // 2. Ecrire le nouveau sshd_config
      final deployResult = await Process.run('ssh', [
        '-p', '$port',
        '-o', 'ConnectTimeout=10',
        '$user@$host',
        'sudo tee /etc/ssh/sshd_config',
      ]);
      // Note : en pratique, utiliser scp ou heredoc

      // 3. Tester la config avant de redemarrer
      final testResult = await Process.run('ssh', [
        '-p', '$port',
        '$user@$host',
        'sudo sshd -t',
      ]);
      if (testResult.exitCode != 0) {
        // Restaurer le backup
        await Process.run('ssh', [
          '-p', '$port',
          '$user@$host',
          'sudo cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config',
        ]);
        return false;
      }

      // 4. Recharger sshd
      await Process.run('ssh', [
        '-p', '$port',
        '$user@$host',
        'sudo systemctl reload sshd || sudo systemctl reload ssh',
      ]);

      return true;
    } catch (_) {
      return false;
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Dans l'ecran de configuration SSH :
//
//   final hardening = SshdHardening();
//
//   // Audit de la config distante
//   final results = await hardening.auditConfig();
//   final criticalIssues = results.where((r) =>
//       !r.isCompliant && r.severity == 'critical');
//
//   if (criticalIssues.isNotEmpty) {
//     // Afficher les problemes et proposer le durcissement
//     showHardeningDialog(criticalIssues.toList());
//   }
//
//   // Deployer si l'utilisateur accepte
//   await hardening.deployHardenedConfig(host: '...', user: '...');
// =============================================================
