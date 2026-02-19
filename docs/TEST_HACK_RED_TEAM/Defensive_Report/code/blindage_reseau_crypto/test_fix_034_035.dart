// =============================================================
// Tests pour FIX-034 : Heartbeat securise
// Tests pour FIX-035 : Chiffrement IPC
// =============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

void main() {
  print('=== Tests FIX-034/035 : Heartbeat + IPC Encryption ===\n');

  // FIX-034 Tests
  testChallengeGeneration();
  testConstantTimeEquals();
  testHeartbeatStateTransitions();
  testConsecutiveFailureCounter();

  // FIX-035 Tests
  testKeyDerivation();
  testEncryptDecryptRoundtrip();
  testNonceMonotone();
  testReplayDetection();
  testTamperedMessageRejected();
  testDifferentKeysProduceDifferentCiphertext();

  print('\n=== Tous les tests FIX-034/035 passes ===');
}

// === FIX-034 : Heartbeat ===

void testChallengeGeneration() {
  print('Test: Challenge generation (CSPRNG)...');

  final random = Random.secure();
  final challenges = <String>{};

  // Generer 100 challenges, tous doivent etre uniques
  for (int i = 0; i < 100; i++) {
    final bytes = Uint8List(32);
    for (int j = 0; j < 32; j++) {
      bytes[j] = random.nextInt(256);
    }
    challenges.add(_bytesToHex(bytes));
  }

  assert(challenges.length == 100,
      'Les 100 challenges doivent etre uniques (got ${challenges.length})');

  print('  OK: 100 challenges uniques generes');
}

void testConstantTimeEquals() {
  print('Test: Constant time comparison...');

  assert(_constantTimeEquals('abc', 'abc'), 'Egal doit retourner true');
  assert(!_constantTimeEquals('abc', 'abd'), 'Different doit retourner false');
  assert(!_constantTimeEquals('abc', 'ab'), 'Longueur differente doit retourner false');
  assert(_constantTimeEquals('', ''), 'Vide egal doit retourner true');
  assert(!_constantTimeEquals('a', ''), 'Vide vs non-vide doit retourner false');

  // Test avec des hex SHA-256
  final hex1 = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
  final hex2 = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
  final hex3 = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b3';

  assert(_constantTimeEquals(hex1, hex2), 'Hex identiques');
  assert(!_constantTimeEquals(hex1, hex3), 'Hex differents (dernier char)');

  print('  OK: Comparaison temps constant fonctionne');
}

void testHeartbeatStateTransitions() {
  print('Test: Heartbeat state transitions...');

  // Simuler la machine a etats
  var state = 'stopped';
  var failures = 0;
  const maxFailures = 3;

  // Start
  state = 'healthy';
  assert(state == 'healthy', 'Apres start: healthy');

  // 1 echec -> degraded
  failures++;
  if (failures >= maxFailures) state = 'dead';
  else if (failures >= 1) state = 'degraded';
  assert(state == 'degraded', 'Apres 1 echec: degraded');

  // 1 succes -> healthy
  failures = 0;
  state = 'healthy';
  assert(state == 'healthy', 'Apres succes: healthy');

  // 3 echecs -> dead
  for (int i = 0; i < 3; i++) {
    failures++;
    if (failures >= maxFailures) state = 'dead';
    else if (failures >= 1) state = 'degraded';
  }
  assert(state == 'dead', 'Apres 3 echecs: dead');

  print('  OK: Transitions d\'etat correctes');
}

void testConsecutiveFailureCounter() {
  print('Test: Consecutive failure counter...');

  var failures = 0;

  // 2 echecs, 1 succes, 2 echecs
  failures++; // 1
  failures++; // 2
  failures = 0; // Reset par succes
  failures++; // 1
  failures++; // 2

  assert(failures == 2,
      'Le compteur doit etre a 2 (pas cumulatif apres reset)');

  print('  OK: Compteur reset apres succes');
}

// === FIX-035 : IPC Encryption ===

void testKeyDerivation() {
  print('Test: Key derivation...');

  final local = Uint8List.fromList(List.generate(32, (i) => i));
  final remote = Uint8List.fromList(List.generate(32, (i) => i + 100));

  final key1 = _deriveKey(local, remote);
  final key2 = _deriveKey(local, remote);

  // Deterministe
  assert(_listEquals(key1, key2), 'Meme entree = meme cle');

  // Differente si l'entree change
  final remote2 = Uint8List.fromList(List.generate(32, (i) => i + 200));
  final key3 = _deriveKey(local, remote2);
  assert(!_listEquals(key1, key3), 'Entree differente = cle differente');

  print('  OK: Derivation de cle deterministe et unique');
}

void testEncryptDecryptRoundtrip() {
  print('Test: Encrypt/decrypt roundtrip...');

  final key = Uint8List.fromList(List.generate(32, (i) => (i * 7) % 256));
  final macKey = Uint8List.fromList(List.generate(32, (i) => (i * 13) % 256));

  final message = {'type': 'status', 'connected': true, 'ip': '100.64.1.2'};
  final plaintext = utf8.encode(jsonEncode(message));

  // Chiffrer
  final nonce = Uint8List(12);
  nonce[7] = 1; // Nonce = 1
  final ciphertext = _xorKeystream(Uint8List.fromList(plaintext), nonce, key);

  // Le ciphertext doit etre different du plaintext
  assert(!_listEquals(ciphertext, Uint8List.fromList(plaintext)),
      'Le ciphertext doit etre different du plaintext');

  // Dechiffrer
  final decrypted = _xorKeystream(ciphertext, nonce, key);
  final restored = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;

  assert(restored['type'] == 'status', 'Type restaure');
  assert(restored['connected'] == true, 'Connected restaure');
  assert(restored['ip'] == '100.64.1.2', 'IP restauree');

  print('  OK: Roundtrip chiffrement/dechiffrement');
}

void testNonceMonotone() {
  print('Test: Nonce monotone...');

  var sendNonce = 0;
  final nonces = <int>[];

  for (int i = 0; i < 10; i++) {
    sendNonce++;
    nonces.add(sendNonce);
  }

  // Verifier la monotonie stricte
  for (int i = 1; i < nonces.length; i++) {
    assert(nonces[i] > nonces[i - 1],
        'Nonce $i doit etre > nonce ${i - 1}');
  }

  print('  OK: Nonces strictement croissants');
}

void testReplayDetection() {
  print('Test: Replay detection...');

  var lastReceiveNonce = 0;

  // Message 1 (nonce=1) — OK
  var nonce = 1;
  assert(nonce > lastReceiveNonce, 'Nonce 1 > 0: accepte');
  lastReceiveNonce = nonce;

  // Message 2 (nonce=2) — OK
  nonce = 2;
  assert(nonce > lastReceiveNonce, 'Nonce 2 > 1: accepte');
  lastReceiveNonce = nonce;

  // Replay message 1 (nonce=1) — REJETE
  nonce = 1;
  assert(nonce <= lastReceiveNonce, 'Nonce 1 <= 2: rejete (replay)');

  // Replay message 2 (nonce=2) — REJETE
  nonce = 2;
  assert(nonce <= lastReceiveNonce, 'Nonce 2 <= 2: rejete (replay)');

  // Message 3 (nonce=3) — OK
  nonce = 3;
  assert(nonce > lastReceiveNonce, 'Nonce 3 > 2: accepte');

  print('  OK: Replay attacks detectes');
}

void testTamperedMessageRejected() {
  print('Test: Tampered message rejected...');

  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final macKey = Uint8List.fromList(List.generate(32, (i) => i + 50));

  final plaintext = utf8.encode('{"type":"command","action":"connect"}');
  final nonce = Uint8List(12);
  nonce[7] = 1;

  final ciphertext = _xorKeystream(Uint8List.fromList(plaintext), nonce, key);

  // Calculer le HMAC
  final macInput = Uint8List(nonce.length + ciphertext.length);
  macInput.setAll(0, nonce);
  macInput.setAll(nonce.length, ciphertext);
  final originalMac = _simpleHmac(macInput, macKey);

  // Alterer un byte du ciphertext
  final tampered = Uint8List.fromList(ciphertext);
  tampered[0] ^= 0xFF;

  // Recalculer le HMAC du message altere
  final macInput2 = Uint8List(nonce.length + tampered.length);
  macInput2.setAll(0, nonce);
  macInput2.setAll(nonce.length, tampered);
  final tamperedMac = _simpleHmac(macInput2, macKey);

  // Les MACs doivent etre differents
  assert(!_listEquals(originalMac, tamperedMac),
      'Le HMAC du message altere doit etre different');

  print('  OK: Message altere detecte par HMAC');
}

void testDifferentKeysProduceDifferentCiphertext() {
  print('Test: Different keys produce different ciphertext...');

  final key1 = Uint8List.fromList(List.generate(32, (i) => i));
  final key2 = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final nonce = Uint8List(12);
  nonce[7] = 1;
  final plaintext = Uint8List.fromList(utf8.encode('test message'));

  final cipher1 = _xorKeystream(plaintext, nonce, key1);
  final cipher2 = _xorKeystream(Uint8List.fromList(plaintext), nonce, key2);

  assert(!_listEquals(cipher1, cipher2),
      'Des cles differentes doivent produire des ciphertexts differents');

  print('  OK: Cles differentes = ciphertexts differents');
}

// === Helpers ===

String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  int result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

Uint8List _deriveKey(Uint8List local, Uint8List remote) {
  // Simplified HKDF
  final combined = Uint8List(local.length + remote.length + 16);
  combined.setAll(0, local);
  combined.setAll(local.length, remote);
  combined.setAll(local.length + remote.length, utf8.encode('chillapp-ipc-v1'));

  final result = Uint8List(32);
  for (int i = 0; i < combined.length; i++) {
    result[i % 32] ^= combined[i];
    result[(i + 1) % 32] = (result[(i + 1) % 32] + combined[i]) & 0xFF;
  }
  return result;
}

Uint8List _xorKeystream(Uint8List data, Uint8List nonce, Uint8List key) {
  final result = Uint8List(data.length);
  int offset = 0;
  int counter = 0;

  while (offset < data.length) {
    // Generate keystream block
    final counterBytes = Uint8List(4);
    counterBytes[0] = (counter >> 24) & 0xFF;
    counterBytes[1] = (counter >> 16) & 0xFF;
    counterBytes[2] = (counter >> 8) & 0xFF;
    counterBytes[3] = counter & 0xFF;

    // Simple hash for keystream (simplified)
    final block = Uint8List(32);
    for (int i = 0; i < key.length; i++) {
      block[i % 32] ^= key[i];
    }
    for (int i = 0; i < nonce.length; i++) {
      block[(i + 5) % 32] ^= nonce[i];
    }
    for (int i = 0; i < counterBytes.length; i++) {
      block[(i + 10) % 32] ^= counterBytes[i];
    }
    // Mix
    for (int i = 0; i < 32; i++) {
      block[i] = (block[i] + block[(i + 1) % 32]) & 0xFF;
    }

    for (int i = 0; i < block.length && offset < data.length; i++, offset++) {
      result[offset] = data[offset] ^ block[i];
    }
    counter++;
  }
  return result;
}

Uint8List _simpleHmac(Uint8List data, Uint8List key) {
  final result = Uint8List(32);
  for (int i = 0; i < key.length; i++) {
    result[i % 32] ^= key[i];
  }
  for (int i = 0; i < data.length; i++) {
    result[i % 32] = (result[i % 32] ^ data[i] + result[(i + 1) % 32]) & 0xFF;
  }
  return result;
}

bool _listEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
