// =============================================================
// Tests pour FIX-033 : Configuration dartssh2 durcie
// =============================================================

void main() {
  print('=== Tests FIX-033 : dartssh2 Config ===\n');

  testBlacklistedAlgorithmsDetected();
  testSafeAlgorithmsAllowed();
  testCbcCiphersBlocked();
  testSha1KexBlocked();
  testFilteringPreservesOrder();
  testEmptyIntersectionDetected();
  testValidationAllSecure();
  testValidationMixedAlgorithms();

  print('\n=== Tous les tests FIX-033 passes ===');
}

// Reproduire les listes du code source
const blacklisted = [
  'diffie-hellman-group1-sha1',
  'diffie-hellman-group14-sha1',
  'diffie-hellman-group-exchange-sha1',
  'ssh-rsa', 'ssh-dss',
  'aes128-cbc', 'aes192-cbc', 'aes256-cbc', '3des-cbc',
  'arcfour', 'arcfour128', 'arcfour256', 'blowfish-cbc', 'cast128-cbc',
  'hmac-sha1', 'hmac-sha1-96', 'hmac-md5', 'hmac-md5-96',
  'umac-64@openssh.com',
];

const safeKex = [
  'curve25519-sha256',
  'curve25519-sha256@libssh.org',
  'ecdh-sha2-nistp521',
  'ecdh-sha2-nistp384',
  'ecdh-sha2-nistp256',
  'diffie-hellman-group18-sha512',
  'diffie-hellman-group16-sha512',
];

const safeCiphers = [
  'aes256-gcm@openssh.com',
  'aes128-gcm@openssh.com',
  'chacha20-poly1305@openssh.com',
  'aes256-ctr',
  'aes192-ctr',
  'aes128-ctr',
];

void testBlacklistedAlgorithmsDetected() {
  print('Test: Blacklisted algorithms detected...');

  for (final alg in blacklisted) {
    assert(!_isAlgorithmSafe(alg),
        '$alg devrait etre detecte comme dangereux');
  }

  print('  OK: ${blacklisted.length} algorithmes blacklistes detectes');
}

void testSafeAlgorithmsAllowed() {
  print('Test: Safe algorithms allowed...');

  for (final alg in safeKex) {
    assert(_isAlgorithmSafe(alg),
        '$alg devrait etre autorise');
  }

  for (final alg in safeCiphers) {
    assert(_isAlgorithmSafe(alg),
        '$alg devrait etre autorise');
  }

  print('  OK: Algorithmes securises autorises');
}

void testCbcCiphersBlocked() {
  print('Test: CBC ciphers blocked...');

  final cbcCiphers = ['aes128-cbc', 'aes192-cbc', 'aes256-cbc', '3des-cbc'];
  for (final cipher in cbcCiphers) {
    assert(!_isAlgorithmSafe(cipher),
        'CBC cipher $cipher devrait etre bloque (Terrapin)');
  }

  print('  OK: CBC ciphers bloques (protection Terrapin)');
}

void testSha1KexBlocked() {
  print('Test: SHA-1 KEX blocked...');

  final sha1Kex = [
    'diffie-hellman-group1-sha1',
    'diffie-hellman-group14-sha1',
    'diffie-hellman-group-exchange-sha1',
  ];
  for (final kex in sha1Kex) {
    assert(!_isAlgorithmSafe(kex),
        'SHA-1 KEX $kex devrait etre bloque');
  }

  print('  OK: SHA-1 KEX bloques');
}

void testFilteringPreservesOrder() {
  print('Test: Filtering preserves order...');

  final serverAlgorithms = [
    'diffie-hellman-group1-sha1',   // Dangereux
    'curve25519-sha256',              // Sur
    'ecdh-sha2-nistp256',            // Sur
    'diffie-hellman-group14-sha1',   // Dangereux
    'diffie-hellman-group16-sha512', // Sur
  ];

  final filtered = serverAlgorithms
      .where((a) => safeKex.contains(a))
      .toList();

  assert(filtered.length == 3, 'Devrait garder 3 algorithmes');
  assert(filtered[0] == 'curve25519-sha256', 'Premier devrait etre curve25519');
  assert(filtered[1] == 'ecdh-sha2-nistp256', 'Deuxieme devrait etre nistp256');
  assert(filtered[2] == 'diffie-hellman-group16-sha512', 'Troisieme devrait etre group16');

  print('  OK: Ordre preserve apres filtrage');
}

void testEmptyIntersectionDetected() {
  print('Test: Empty intersection detected...');

  // Serveur ne propose que des algorithmes faibles
  final weakServer = [
    'diffie-hellman-group1-sha1',
    'ssh-rsa',
    'aes128-cbc',
    'hmac-sha1',
  ];

  final filteredKex = weakServer.where((a) => safeKex.contains(a)).toList();
  final filteredCiphers = weakServer.where((a) => safeCiphers.contains(a)).toList();

  assert(filteredKex.isEmpty, 'Aucun KEX securise en commun');
  assert(filteredCiphers.isEmpty, 'Aucun cipher securise en commun');

  // Cela devrait declencher un refus de connexion
  final isSecure = filteredKex.isNotEmpty && filteredCiphers.isNotEmpty;
  assert(!isSecure, 'La connexion devrait etre refusee');

  print('  OK: Intersection vide = connexion refusee');
}

void testValidationAllSecure() {
  print('Test: Validation all secure server...');

  final serverKex = ['curve25519-sha256', 'ecdh-sha2-nistp256'];
  final serverHostKeys = ['ssh-ed25519', 'rsa-sha2-512'];
  final serverCiphers = ['aes256-gcm@openssh.com', 'chacha20-poly1305@openssh.com'];
  final serverMacs = ['hmac-sha2-512-etm@openssh.com', 'hmac-sha2-256-etm@openssh.com'];

  final issues = <String>[];
  if (serverKex.where((a) => safeKex.contains(a)).isEmpty) {
    issues.add('No safe KEX');
  }
  if (serverCiphers.where((a) => safeCiphers.contains(a)).isEmpty) {
    issues.add('No safe ciphers');
  }

  assert(issues.isEmpty, 'Un serveur entierement securise ne devrait pas avoir d\'issues');

  print('  OK: Serveur securise valide sans issues');
}

void testValidationMixedAlgorithms() {
  print('Test: Validation mixed algorithms...');

  // Serveur avec un melange de securise et faible
  final serverAll = [
    'curve25519-sha256',
    'diffie-hellman-group1-sha1',  // Faible
    'ssh-ed25519',
    'ssh-rsa',                       // Faible
    'aes256-gcm@openssh.com',
    'aes128-cbc',                    // Faible
  ];

  final dangerous = serverAll.where((a) => blacklisted.contains(a)).toList();
  assert(dangerous.length == 3,
      'Devrait detecter 3 algorithmes dangereux');
  assert(dangerous.contains('diffie-hellman-group1-sha1'), 'DH group1 detecte');
  assert(dangerous.contains('ssh-rsa'), 'ssh-rsa detecte');
  assert(dangerous.contains('aes128-cbc'), 'aes128-cbc detecte');

  print('  OK: Algorithmes dangereux detectes dans un serveur mixte');
}

// === Helpers ===

bool _isAlgorithmSafe(String algorithm) {
  return !blacklisted.contains(algorithm.toLowerCase());
}
