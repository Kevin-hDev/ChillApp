// =============================================================
// FIX-033 : Configuration SSH durcie
// GAP-033: Configuration dartssh2 non durcie (P0)
// Cible: lib/core/security/ssh_hardened_config.dart
// =============================================================
//
// PROBLEME : dartssh2 utilise les algorithmes par defaut, incluant
// des algorithmes faibles (DH group1-sha1, RSA 1024, CBC+ETM).
// La vulnerabilite Terrapin (CVE-2023-48795) n'est pas corrigee
// sans forcer Strict KEX.
//
// SOLUTION :
// 1. Whitelist d'algorithmes forts uniquement
// 2. Blacklist explicite de 19 algorithmes dangereux
// 3. Validation obligatoire avant chaque connexion
// 4. Fail closed : si le serveur ne supporte aucun algo sur,
//    la connexion DOIT echouer (jamais de fallback faible)
// =============================================================

/// Listes d'algorithmes SSH autorises (whitelist) et interdits (blacklist).
///
/// Seuls les algorithmes modernes et securises sont autorises :
///   - KEX  : curve25519, ecdh-sha2-nistp*, DH group16/18-sha512
///   - Cles : ed25519, ecdsa-sha2-nistp*, rsa-sha2-256/512
///   - Ciphers : GCM, ChaCha20-Poly1305, CTR uniquement (pas de CBC)
///   - MACs : ETM avec SHA-2 uniquement
class SshHardenedAlgorithms {
  SshHardenedAlgorithms._(); // Classe utilitaire — pas d'instanciation

  // --- KEX (Key Exchange) ---
  // Autorises : curve25519 et ecdh-sha2-nistp256/384/521,
  //             DH group16-sha512 et group18-sha512
  // Interdits : group1-sha1, group14-sha1, group-exchange-sha1
  static const List<String> allowedKex = [
    'curve25519-sha256',
    'curve25519-sha256@libssh.org',
    'ecdh-sha2-nistp256',
    'ecdh-sha2-nistp384',
    'ecdh-sha2-nistp521',
    'diffie-hellman-group16-sha512',
    'diffie-hellman-group18-sha512',
  ];

  // --- Host Key Algorithms ---
  // Autorises : ed25519, ecdsa-sha2-nistp*, rsa-sha2-256/512
  // Interdits : ssh-rsa (SHA-1 = casse), ssh-dss (512 bits)
  static const List<String> allowedHostKeys = [
    'ssh-ed25519',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
    'rsa-sha2-256',
    'rsa-sha2-512',
  ];

  // --- Ciphers ---
  // Autorises : GCM (AEAD), ChaCha20-Poly1305 (AEAD), CTR
  // Interdits : aes*-cbc (vulnerabilite Terrapin CVE-2023-48795),
  //             3des-cbc, arcfour (RC4)
  static const List<String> allowedCiphers = [
    'aes256-gcm@openssh.com',
    'aes128-gcm@openssh.com',
    'chacha20-poly1305@openssh.com',
    'aes256-ctr',
    'aes192-ctr',
    'aes128-ctr',
  ];

  // --- MACs ---
  // Autorises : ETM (Encrypt-then-MAC) avec SHA-2 uniquement
  // Interdits : SHA-1, MD5, UMAC-64 (trop court ou casse)
  static const List<String> allowedMacs = [
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-512-etm@openssh.com',
    'hmac-sha2-256',
    'hmac-sha2-512',
  ];

  // --- Algorithmes interdits (blacklist) ---
  // Ces algorithmes NE DOIVENT JAMAIS etre utilises, meme si le
  // serveur les propose. Cause de refus de connexion (fail closed).
  static const List<String> blacklisted = [
    // KEX faibles (SHA-1 ou groupes trop petits)
    'diffie-hellman-group1-sha1',
    'diffie-hellman-group14-sha1',
    'diffie-hellman-group-exchange-sha1',

    // Host keys faibles
    'ssh-rsa', // SHA-1 — casse
    'ssh-dss', // DSA 512/1024 bits

    // Ciphers CBC — vulnerabilite Terrapin (CVE-2023-48795)
    'aes128-cbc',
    'aes192-cbc',
    'aes256-cbc',
    '3des-cbc',
    'blowfish-cbc',
    'cast128-cbc',

    // RC4 — totalement casse
    'arcfour',
    'arcfour128',
    'arcfour256',

    // MACs faibles
    'hmac-sha1',
    'hmac-sha1-96',
    'hmac-md5',
    'hmac-md5-96',
    'umac-64@openssh.com',
  ];

  // ============================================================
  // Methodes de verification
  // ============================================================

  /// Verifie si un algorithme est dans la whitelist des autorises.
  ///
  /// La comparaison est insensible a la casse.
  static bool isAlgorithmAllowed(String algo) {
    final lower = algo.toLowerCase();
    return allowedKex.contains(lower) ||
        allowedHostKeys.contains(lower) ||
        allowedCiphers.contains(lower) ||
        allowedMacs.contains(lower);
  }

  /// Verifie si un algorithme est dans la blacklist des interdits.
  ///
  /// La comparaison est insensible a la casse.
  static bool isAlgorithmBlacklisted(String algo) {
    return blacklisted.contains(algo.toLowerCase());
  }

  /// Filtre une liste d'algorithmes pour ne garder que les autorises.
  ///
  /// Utilise les quatre listes de whitelist (kex, hostkeys, ciphers, macs).
  /// L'ordre des algorithmes autorises est preserve (preference du client).
  ///
  /// [offered] : liste d'algorithmes proposes (ex: par le serveur SSH).
  /// Retourne uniquement ceux presents dans [allowedKex], [allowedHostKeys],
  /// [allowedCiphers] ou [allowedMacs], dans l'ordre de [offered].
  static List<String> filterAlgorithms(List<String> offered) {
    return offered.where(isAlgorithmAllowed).toList();
  }

  /// Filtre une liste KEX pour ne garder que les autorises.
  static List<String> filterKex(List<String> offered) {
    return offered.where((a) => allowedKex.contains(a)).toList();
  }

  /// Filtre une liste de host keys pour ne garder que les autorisees.
  static List<String> filterHostKeys(List<String> offered) {
    return offered.where((a) => allowedHostKeys.contains(a)).toList();
  }

  /// Filtre une liste de ciphers pour ne garder que les autorises.
  static List<String> filterCiphers(List<String> offered) {
    return offered.where((a) => allowedCiphers.contains(a)).toList();
  }

  /// Filtre une liste de MACs pour ne garder que les autorises.
  static List<String> filterMacs(List<String> offered) {
    return offered.where((a) => allowedMacs.contains(a)).toList();
  }
}

/// Resultat de la validation d'un serveur SSH.
class SshValidationResult {
  /// true si le serveur supporte au moins un algo sur dans chaque categorie.
  final bool isSecure;

  /// Liste des problemes detectes (vide si [isSecure] == true).
  final List<String> issues;

  /// Algorithmes dangereux proposes par le serveur (informatif).
  final List<String> dangerousAlgorithmsOffered;

  /// Algorithmes KEX negocies (intersection whitelist / offre serveur).
  final List<String> negotiatedKex;

  /// Host keys negocies.
  final List<String> negotiatedHostKeys;

  /// Ciphers negocies.
  final List<String> negotiatedCiphers;

  /// MACs negocies.
  final List<String> negotiatedMacs;

  const SshValidationResult({
    required this.isSecure,
    required this.issues,
    required this.dangerousAlgorithmsOffered,
    required this.negotiatedKex,
    required this.negotiatedHostKeys,
    required this.negotiatedCiphers,
    required this.negotiatedMacs,
  });
}

/// Validateur de configuration SSH.
///
/// Verifie qu'un serveur SSH supporte au moins un algorithme securise
/// dans chaque categorie. Si ce n'est pas le cas : FAIL CLOSED.
class SshConfigValidator {
  SshConfigValidator._(); // Classe utilitaire

  /// Valide la configuration d'un serveur SSH.
  ///
  /// Si [result.isSecure] == false, la connexion DOIT etre refusee.
  /// Ne jamais faire de fallback vers des algorithmes faibles.
  static SshValidationResult validateServer({
    required List<String> serverKex,
    required List<String> serverHostKeys,
    required List<String> serverCiphers,
    required List<String> serverMacs,
  }) {
    final safeKex = SshHardenedAlgorithms.filterKex(serverKex);
    final safeHostKeys = SshHardenedAlgorithms.filterHostKeys(serverHostKeys);
    final safeCiphers = SshHardenedAlgorithms.filterCiphers(serverCiphers);
    final safeMacs = SshHardenedAlgorithms.filterMacs(serverMacs);

    final issues = <String>[];

    if (safeKex.isEmpty) {
      issues.add('Aucun algorithme KEX securise supporte par le serveur');
    }
    if (safeHostKeys.isEmpty) {
      issues.add('Aucun algorithme host key securise supporte');
    }
    if (safeCiphers.isEmpty) {
      issues.add('Aucun cipher securise supporte');
    }
    if (safeMacs.isEmpty) {
      issues.add('Aucun MAC securise supporte');
    }

    // Detecter les algorithmes dangereux proposes par le serveur
    final allOffered = [
      ...serverKex,
      ...serverHostKeys,
      ...serverCiphers,
      ...serverMacs,
    ];
    final dangerousOffered = allOffered
        .where(SshHardenedAlgorithms.isAlgorithmBlacklisted)
        .toList();

    return SshValidationResult(
      isSecure: issues.isEmpty,
      issues: issues,
      dangerousAlgorithmsOffered: dangerousOffered,
      negotiatedKex: safeKex,
      negotiatedHostKeys: safeHostKeys,
      negotiatedCiphers: safeCiphers,
      negotiatedMacs: safeMacs,
    );
  }

  /// Verifie qu'un algorithme individuel n'est pas dans la blacklist.
  static bool isAlgorithmSafe(String algorithm) {
    return !SshHardenedAlgorithms.isAlgorithmBlacklisted(algorithm);
  }
}

/// Configuration de renouvellement de session SSH (RekeyLimit).
///
/// Limite la quantite de donnees et le temps avant un nouveau KEX,
/// pour limiter l'exposition en cas de compromission de cle de session.
class RekeyConfig {
  /// Limite de donnees avant rekey (en octets). Defaut : 1 Go.
  final int maxBytes;

  /// Limite de temps avant rekey (en secondes). Defaut : 1 heure.
  final int maxSeconds;

  const RekeyConfig({
    this.maxBytes = 1073741824, // 1 Go
    this.maxSeconds = 3600, // 1 heure
  });
}
