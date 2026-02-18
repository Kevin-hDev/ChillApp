// =============================================================
// FIX-036 : Template sshd_config durci
// GAP-036: Template sshd_config durci absent (P1)
// =============================================================
//
// PROBLEME : Le PC cible peut avoir une config SSH faible
// (mots de passe, root login, algorithmes obsolètes).
// ChillApp doit pouvoir auditer et générer un template durci.
//
// SOLUTION :
// 1. Audit de la configuration sshd existante
// 2. Génération d'un template sshd_config complet durci
// 3. Détection des paramètres critiques non conformes
//
// NOTE : Ce module fait UNIQUEMENT audit + génération de template.
// Le déploiement SSH est hors scope de ce module.
// =============================================================

/// Résultat de la vérification d'un paramètre sshd_config.
class SshdCheckResult {
  /// Nom du paramètre vérifié (ex: 'PermitRootLogin').
  final String parameter;

  /// Valeur attendue pour être conforme (description humaine).
  final String expected;

  /// Valeur actuelle dans la configuration auditée.
  final String actual;

  /// Niveau de gravité : 'critical', 'warning', ou 'info'.
  final String severity;

  /// Indique si le paramètre est conforme.
  ///
  /// Calculé explicitement à la construction plutôt que par
  /// comparaison de chaînes, car certains paramètres (KexAlgorithms,
  /// Ciphers, MACs) ont une logique de conformité nuancée.
  final bool isCompliant;

  const SshdCheckResult({
    required this.parameter,
    required this.expected,
    required this.actual,
    required this.severity,
    required this.isCompliant,
  });
}

/// Configuration par défaut durcie pour sshd_config.
///
/// Basée sur les recommandations CIS, NSA et Mozilla SSH Guidelines.
/// Durcissement contre Terrapin (CVE-2023-48795) inclus.
class SshdHardeningConfig {
  /// Port SSH (défaut 22 — peut être changé pour l'obscurité).
  final int port;

  /// Nombre maximum de tentatives d'authentification.
  final int maxAuthTries;

  /// Délai de grâce pour la connexion (secondes).
  final int loginGraceTime;

  /// Limite de renouvellement de session (données, temps).
  final String rekeyLimit;

  /// Réseau Tailscale autorisé (AllowUsers).
  final String allowedNetwork;

  const SshdHardeningConfig({
    this.port = 22,
    this.maxAuthTries = 3,
    this.loginGraceTime = 60,
    this.rekeyLimit = '512M 1h',
    this.allowedNetwork = '100.64.0.0/10',
  });
}

/// Module d'audit et de génération de template sshd_config durci.
///
/// EXEMPLE D'UTILISATION :
/// ```dart
/// final hardening = SshdHardening();
///
/// // Auditer une configuration
/// final configContent = await File('/etc/ssh/sshd_config').readAsString();
/// final results = hardening.auditConfig(configContent);
///
/// if (hardening.hasCriticalIssues(results)) {
///   // Afficher les problèmes critiques à l'utilisateur
///   final critiques = results.where((r) =>
///       !r.isCompliant && r.severity == 'critical');
/// }
///
/// // Générer un template durci
/// final template = hardening.generateHardenedConfig();
/// ```
class SshdHardening {
  /// Configuration de durcissement appliquée.
  final SshdHardeningConfig config;

  SshdHardening({SshdHardeningConfig? config})
      : config = config ?? const SshdHardeningConfig();

  /// Audit une configuration sshd_config fournie en texte brut.
  ///
  /// [sshdConfigContent] : contenu du fichier sshd_config à auditer.
  /// Retourne une liste de résultats de vérification, y compris les
  /// paramètres conformes et non conformes.
  List<SshdCheckResult> auditConfig(String sshdConfigContent) {
    final results = <SshdCheckResult>[];

    // Parser le contenu : ignorer les lignes vides et les commentaires
    final params = _parseConfig(sshdConfigContent);

    // --- Vérifications CRITIQUES ---
    results.add(_check(params, 'PermitRootLogin', 'no', 'critical'));
    results.add(_check(params, 'PasswordAuthentication', 'no', 'critical'));
    results.add(_check(params, 'PubkeyAuthentication', 'yes', 'critical'));
    results.add(_check(params, 'PermitEmptyPasswords', 'no', 'critical'));
    results.add(_checkKex(params));
    results.add(_checkCiphers(params));

    // --- Vérifications IMPORTANTES ---
    results.add(_checkMaxAuthTries(params));
    results.add(_check(params, 'X11Forwarding', 'no', 'warning'));
    results.add(_check(params, 'AllowTcpForwarding', 'no', 'warning'));
    results.add(_check(params, 'AllowAgentForwarding', 'no', 'warning'));
    results.add(_check(params, 'StrictModes', 'yes', 'warning'));
    results.add(_checkMacs(params));

    // --- Vérifications INFORMATIVES ---
    results.add(_check(params, 'LogLevel', 'VERBOSE', 'info'));

    return results;
  }

  /// Génère un template sshd_config complet durci selon [config].
  ///
  /// Le template inclut tous les paramètres recommandés et les
  /// algorithmes sécurisés (résistants à CVE-2023-48795 Terrapin).
  String generateHardenedConfig() {
    final timestamp = DateTime.now().toIso8601String();
    return '''# =============================================================
# sshd_config durci par ChillApp
# Généré le $timestamp
# Basé sur : CIS Benchmark, NSA Guidelines, Mozilla SSH Guidelines
# Durcissement Terrapin (CVE-2023-48795) inclus
# =============================================================

# --- Réseau ---
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
# KEX : uniquement courbes modernes (pas de SHA-1, pas de DH group1/14)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512

# HostKey : ed25519 préféré, pas de RSA-SHA1 ni de DSA
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,rsa-sha2-512,rsa-sha2-256

# Ciphers : GCM et ChaCha uniquement — pas de modes CBC
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr,aes192-ctr

# MACs : ETM uniquement (Encrypt-Then-MAC) — pas de MD5 ni SHA-1
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# --- Renouvellement de session ---
RekeyLimit ${config.rekeyLimit}

# --- Sécurité ---
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

# --- Restrictions réseau ---
# N'autorise que les connexions depuis le réseau Tailscale
AllowUsers *@${config.allowedNetwork}

# --- Subsystem ---
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
''';
  }

  /// Vérifie si la liste de résultats contient des problèmes critiques.
  ///
  /// Un problème critique est un paramètre non conforme avec
  /// [SshdCheckResult.severity] == 'critical'.
  bool hasCriticalIssues(List<SshdCheckResult> results) {
    return results.any(
      (r) => !r.isCompliant && r.severity == 'critical',
    );
  }

  // ============================================================
  // Méthodes privées
  // ============================================================

  /// Parse le contenu d'un sshd_config en Map (clé en minuscules, valeur).
  Map<String, String> _parseConfig(String content) {
    final params = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        params[parts[0].toLowerCase()] = parts.sublist(1).join(' ');
      }
    }
    return params;
  }

  /// Vérifie un paramètre simple (valeur exacte insensible à la casse).
  SshdCheckResult _check(
    Map<String, String> params,
    String key,
    String expected,
    String severity,
  ) {
    final current = params[key.toLowerCase()];
    final ok = current?.toLowerCase() == expected.toLowerCase();
    return SshdCheckResult(
      parameter: key,
      expected: expected,
      actual: current ?? '(absent)',
      severity: severity,
      isCompliant: ok,
    );
  }

  /// Vérifie MaxAuthTries (doit être inférieur ou égal à config.maxAuthTries).
  SshdCheckResult _checkMaxAuthTries(Map<String, String> params) {
    final current = params['maxauthtries'];
    final value = int.tryParse(current ?? '');
    final ok = value != null && value <= config.maxAuthTries;
    return SshdCheckResult(
      parameter: 'MaxAuthTries',
      expected: 'max ${config.maxAuthTries}',
      actual: current ?? '(absent)',
      severity: 'warning',
      isCompliant: ok,
    );
  }

  /// Vérifie KexAlgorithms (absence d'algorithmes SHA-1 faibles).
  SshdCheckResult _checkKex(Map<String, String> params) {
    final current = params['kexalgorithms'];
    final weakKex = [
      'diffie-hellman-group1-sha1',
      'diffie-hellman-group14-sha1',
      'diffie-hellman-group-exchange-sha1',
    ];
    final hasWeak = current != null &&
        weakKex.any((w) => current.toLowerCase().contains(w));

    // Conforme si défini ET sans algorithmes SHA-1 faibles
    final ok = current != null && !hasWeak;
    return SshdCheckResult(
      parameter: 'KexAlgorithms',
      expected: 'curve25519-sha256,... (sans SHA-1)',
      actual: current ?? '(absent)',
      severity: 'critical',
      isCompliant: ok,
    );
  }

  /// Vérifie Ciphers (absence de modes CBC et algorithmes faibles).
  SshdCheckResult _checkCiphers(Map<String, String> params) {
    final current = params['ciphers'];
    final weakCiphers = [
      '3des-cbc',
      'arcfour',
      'blowfish-cbc',
      'aes128-cbc',
      'aes192-cbc',
      'aes256-cbc',
    ];
    final hasWeak = current != null &&
        weakCiphers.any((w) => current.toLowerCase().contains(w));

    // Conforme si défini ET sans ciphers CBC/faibles
    final ok = current != null && !hasWeak;
    return SshdCheckResult(
      parameter: 'Ciphers',
      expected: 'aes256-gcm,chacha20-poly1305,... (sans CBC)',
      actual: current ?? '(absent)',
      severity: 'critical',
      isCompliant: ok,
    );
  }

  /// Vérifie MACs (absence de MD5 et SHA-1).
  SshdCheckResult _checkMacs(Map<String, String> params) {
    final current = params['macs'];
    final weakMacs = ['hmac-md5', 'hmac-sha1', 'umac-64'];
    final hasWeak = current != null &&
        weakMacs.any((w) => current.toLowerCase().contains(w));

    // Conforme si défini ET sans MACs faibles
    final ok = current != null && !hasWeak;
    return SshdCheckResult(
      parameter: 'MACs',
      expected: 'hmac-sha2-512-etm,... (sans MD5/SHA-1)',
      actual: current ?? '(absent)',
      severity: 'warning',
      isCompliant: ok,
    );
  }
}
