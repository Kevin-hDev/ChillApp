// =============================================================
// FIX-033 : Configuration dartssh2 durcie
// GAP-033: Configuration dartssh2 non durcie (P0)
// Cible: lib/core/security/ssh_hardened_config.dart (nouveau)
// =============================================================
//
// PROBLEME : dartssh2 utilise les algorithmes par defaut, incluant
// des algorithmes faibles (DH group1-sha1, RSA 1024, CBC+ETM).
// La vulnerabilite Terrapin (CVE-2023-48795) n'est pas corrigee
// sans forcer Strict KEX.
//
// SOLUTION :
// 1. Whitelist d'algorithmes forts uniquement
// 2. Interdire CBC+ETM, DH group1, RSA < 2048
// 3. Forcer curve25519-sha256 et aes256-gcm
// 4. Valider la configuration a chaque connexion
// =============================================================

/// Algorithmes KEX (Key Exchange) autorises.
/// Seuls les algorithmes modernes et securises.
class SshHardenedAlgorithms {
  // --- KEX (Key Exchange) ---
  // Autorises : curve25519 et ecdh-sha2-nistp256/384/521
  // Interdits : diffie-hellman-group1-sha1, group14-sha1, group-exchange-sha1
  static const List<String> kexAlgorithms = [
    'curve25519-sha256',
    'curve25519-sha256@libssh.org',
    'ecdh-sha2-nistp521',
    'ecdh-sha2-nistp384',
    'ecdh-sha2-nistp256',
    'diffie-hellman-group18-sha512',
    'diffie-hellman-group16-sha512',
  ];

  // --- Host Key Algorithms ---
  // Autorises : ed25519, ecdsa, rsa-sha2-512/256
  // Interdits : ssh-rsa (SHA-1), ssh-dss
  static const List<String> hostKeyAlgorithms = [
    'ssh-ed25519',
    'ecdsa-sha2-nistp521',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp256',
    'rsa-sha2-512',
    'rsa-sha2-256',
  ];

  // --- Ciphers ---
  // Autorises : GCM et CTR modes uniquement
  // Interdits : aes*-cbc (CBC+ETM = Terrapin), 3des-cbc, arcfour
  static const List<String> ciphers = [
    'aes256-gcm@openssh.com',
    'aes128-gcm@openssh.com',
    'chacha20-poly1305@openssh.com',
    'aes256-ctr',
    'aes192-ctr',
    'aes128-ctr',
  ];

  // --- MACs ---
  // Autorises : ETM (encrypt-then-MAC) avec SHA-2
  // Interdits : hmac-sha1, hmac-md5, umac-64
  static const List<String> macs = [
    'hmac-sha2-512-etm@openssh.com',
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-512',
    'hmac-sha2-256',
  ];

  // --- Compression ---
  // Desactivee (evite les oracle attacks type BREACH/CRIME)
  static const List<String> compression = [
    'none',
  ];

  /// Algorithmes interdits — a rejeter si proposes par le serveur.
  static const List<String> blacklistedAlgorithms = [
    // KEX faibles
    'diffie-hellman-group1-sha1',
    'diffie-hellman-group14-sha1',
    'diffie-hellman-group-exchange-sha1',
    // Host keys faibles
    'ssh-rsa',  // SHA-1
    'ssh-dss',
    // Ciphers faibles (CBC = Terrapin)
    'aes128-cbc',
    'aes192-cbc',
    'aes256-cbc',
    '3des-cbc',
    'arcfour',
    'arcfour128',
    'arcfour256',
    'blowfish-cbc',
    'cast128-cbc',
    // MACs faibles
    'hmac-sha1',
    'hmac-sha1-96',
    'hmac-md5',
    'hmac-md5-96',
    'umac-64@openssh.com',
  ];
}

/// Validateur de configuration SSH.
class SshConfigValidator {
  /// Verifie qu'un algorithme n'est pas dans la blacklist.
  static bool isAlgorithmSafe(String algorithm) {
    return !SshHardenedAlgorithms.blacklistedAlgorithms.contains(
      algorithm.toLowerCase(),
    );
  }

  /// Filtre une liste d'algorithmes proposes par le serveur.
  /// Ne garde que ceux dans notre whitelist.
  static List<String> filterKex(List<String> serverAlgorithms) {
    return serverAlgorithms
        .where((a) => SshHardenedAlgorithms.kexAlgorithms.contains(a))
        .toList();
  }

  static List<String> filterHostKeys(List<String> serverAlgorithms) {
    return serverAlgorithms
        .where((a) => SshHardenedAlgorithms.hostKeyAlgorithms.contains(a))
        .toList();
  }

  static List<String> filterCiphers(List<String> serverAlgorithms) {
    return serverAlgorithms
        .where((a) => SshHardenedAlgorithms.ciphers.contains(a))
        .toList();
  }

  static List<String> filterMacs(List<String> serverAlgorithms) {
    return serverAlgorithms
        .where((a) => SshHardenedAlgorithms.macs.contains(a))
        .toList();
  }

  /// Valide qu'un serveur supporte au moins un algorithme securise
  /// dans chaque categorie.
  static SshValidationResult validateServer({
    required List<String> serverKex,
    required List<String> serverHostKeys,
    required List<String> serverCiphers,
    required List<String> serverMacs,
  }) {
    final safeKex = filterKex(serverKex);
    final safeHostKeys = filterHostKeys(serverHostKeys);
    final safeCiphers = filterCiphers(serverCiphers);
    final safeMacs = filterMacs(serverMacs);

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

    // Detecter les algorithmes dangereux proposes
    final dangerousOffered = <String>[];
    for (final alg in [...serverKex, ...serverHostKeys, ...serverCiphers, ...serverMacs]) {
      if (SshHardenedAlgorithms.blacklistedAlgorithms.contains(alg)) {
        dangerousOffered.add(alg);
      }
    }

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
}

/// Resultat de la validation d'un serveur SSH.
class SshValidationResult {
  final bool isSecure;
  final List<String> issues;
  final List<String> dangerousAlgorithmsOffered;
  final List<String> negotiatedKex;
  final List<String> negotiatedHostKeys;
  final List<String> negotiatedCiphers;
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

/// Configuration de renouvellement de session (RekeyLimit).
class RekeyConfig {
  /// Limite de donnees avant rekey (en octets). 1 Go par defaut.
  final int maxBytes;

  /// Limite de temps avant rekey (en secondes). 1 heure par defaut.
  final int maxSeconds;

  const RekeyConfig({
    this.maxBytes = 1073741824, // 1 Go
    this.maxSeconds = 3600,     // 1 heure
  });
}

// =============================================================
// INTEGRATION avec dartssh2 :
// =============================================================
//
// import 'package:dartssh2/dartssh2.dart';
//
// final client = SSHClient(
//   socket,
//   username: 'user',
//   identities: [identity],
//   // Forcer les algorithmes securises :
//   algorithms: SSHAlgorithms(
//     kex: SshHardenedAlgorithms.kexAlgorithms
//         .map((name) => kexAlgorithmsByName[name])
//         .whereType<SSHKexAlgorithm>()
//         .toList(),
//     cipher: SshHardenedAlgorithms.ciphers
//         .map((name) => cipherAlgorithmsByName[name])
//         .whereType<SSHCipherAlgorithm>()
//         .toList(),
//     mac: SshHardenedAlgorithms.macs
//         .map((name) => macAlgorithmsByName[name])
//         .whereType<SSHMacAlgorithm>()
//         .toList(),
//     hostkey: SshHardenedAlgorithms.hostKeyAlgorithms
//         .map((name) => hostkeyAlgorithmsByName[name])
//         .whereType<SSHHostkeyAlgorithm>()
//         .toList(),
//   ),
// );
//
// IMPORTANT : Si le serveur ne supporte aucun algorithme securise,
// la connexion DOIT echouer (fail closed). Ne jamais fallback
// vers des algorithmes faibles.
// =============================================================
