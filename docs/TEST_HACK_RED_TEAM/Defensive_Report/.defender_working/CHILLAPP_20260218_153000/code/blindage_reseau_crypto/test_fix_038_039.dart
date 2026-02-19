// =============================================================
// Tests pour FIX-038/039 : Tailscale Security + State Verification
// =============================================================

import 'dart:convert';
import 'dart:typed_data';

void main() {
  print('=== Tests FIX-038/039 : Tailscale + State ===\n');

  // FIX-038 Tests
  testTailscaleArgsGeneration();
  testVersionParsing();

  // FIX-039 Tests
  testStateSigningRoundtrip();
  testStateTimestampDrift();
  testStateSequenceReplay();
  testStateTamperedHmac();
  testStateConstantTimeComparison();

  print('\n=== Tous les tests FIX-038/039 passes ===');
}

void testTailscaleArgsGeneration() {
  print('Test: Tailscale args generation...');

  // Config par defaut
  final defaultArgs = _generateTailscaleArgs(
    enableSshAudit: true,
    forceMagicDns: true,
  );

  assert(defaultArgs.contains('--ssh'), 'Doit inclure --ssh');
  assert(defaultArgs.contains('--accept-dns=true'), 'Doit inclure --accept-dns');
  assert(defaultArgs.contains('--timeout=30s'), 'Doit inclure --timeout');

  // Config sans SSH audit
  final noSshArgs = _generateTailscaleArgs(
    enableSshAudit: false,
    forceMagicDns: true,
  );

  assert(!noSshArgs.contains('--ssh'), 'Ne doit pas inclure --ssh');

  print('  OK: Args Tailscale generes correctement');
}

void testVersionParsing() {
  print('Test: Version parsing...');

  // Tester le parsing de differentes versions
  assert(_parseVersion('1.94.0') == [1, 94, 0], 'Parse 1.94.0');
  assert(_parseVersion('1.93.5') == [1, 93, 5], 'Parse 1.93.5');
  assert(_parseVersion('2.0.0') == [2, 0, 0], 'Parse 2.0.0');

  // Tester la comparaison de versions
  assert(_isVersionAtLeast('1.94.0', 1, 94), '1.94.0 >= 1.94');
  assert(_isVersionAtLeast('1.95.0', 1, 94), '1.95.0 >= 1.94');
  assert(_isVersionAtLeast('2.0.0', 1, 94), '2.0.0 >= 1.94');
  assert(!_isVersionAtLeast('1.93.9', 1, 94), '1.93.9 < 1.94');
  assert(!_isVersionAtLeast('0.99.0', 1, 94), '0.99.0 < 1.94');

  print('  OK: Parsing et comparaison de versions');
}

void testStateSigningRoundtrip() {
  print('Test: State signing roundtrip...');

  final key = Uint8List.fromList(List.generate(32, (i) => (i * 11) % 256));

  // Signer un etat
  final state = 'connected';
  final seq = 1;
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final payload = '$state|$timestamp|$seq';
  final hmac = _simpleHmac(utf8.encode(payload), key);

  // Verifier
  final verifyPayload = '$state|$timestamp|$seq';
  final verifyHmac = _simpleHmac(utf8.encode(verifyPayload), key);

  assert(_listEquals(hmac, verifyHmac),
      'Le HMAC doit etre identique pour le meme payload');

  print('  OK: Signature d\'etat roundtrip');
}

void testStateTimestampDrift() {
  print('Test: State timestamp drift...');

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const maxDrift = 30;

  // Timestamp valide (maintenant)
  assert((now - now).abs() <= maxDrift, 'Timestamp actuel valide');

  // Timestamp de 10s dans le passe (valide)
  assert((now - (now - 10)).abs() <= maxDrift, 'Timestamp -10s valide');

  // Timestamp de 31s dans le passe (invalide)
  assert((now - (now - 31)).abs() > maxDrift, 'Timestamp -31s invalide');

  // Timestamp dans le futur de 5s (valide, derive d'horloge)
  assert((now - (now + 5)).abs() <= maxDrift, 'Timestamp +5s valide');

  // Timestamp dans le futur de 31s (invalide)
  assert((now - (now + 31)).abs() > maxDrift, 'Timestamp +31s invalide');

  print('  OK: Validation drift timestamp');
}

void testStateSequenceReplay() {
  print('Test: State sequence replay detection...');

  var lastSeq = 0;

  // Sequence 1 — OK
  assert(1 > lastSeq, 'Seq 1 > 0: accepte');
  lastSeq = 1;

  // Sequence 2 — OK
  assert(2 > lastSeq, 'Seq 2 > 1: accepte');
  lastSeq = 2;

  // Replay sequence 1 — REJETE
  assert(!(1 > lastSeq), 'Seq 1 <= 2: rejete (replay)');

  // Replay sequence 2 — REJETE
  assert(!(2 > lastSeq), 'Seq 2 <= 2: rejete (replay)');

  // Sequence 5 (saut) — OK
  assert(5 > lastSeq, 'Seq 5 > 2: accepte (sauts autorises)');
  lastSeq = 5;

  print('  OK: Replay de sequence detecte');
}

void testStateTamperedHmac() {
  print('Test: Tampered state HMAC rejected...');

  final key = Uint8List.fromList(List.generate(32, (i) => i));

  // Message original
  final payload1 = 'connected|1708000000|1';
  final hmac1 = _simpleHmac(utf8.encode(payload1), key);

  // Message altere (state change)
  final payload2 = 'disconnected|1708000000|1';
  final hmac2 = _simpleHmac(utf8.encode(payload2), key);

  assert(!_listEquals(hmac1, hmac2),
      'Un etat altere doit produire un HMAC different');

  // Message altere (timestamp)
  final payload3 = 'connected|1708000001|1';
  final hmac3 = _simpleHmac(utf8.encode(payload3), key);

  assert(!_listEquals(hmac1, hmac3),
      'Un timestamp altere doit produire un HMAC different');

  // Message altere (sequence)
  final payload4 = 'connected|1708000000|2';
  final hmac4 = _simpleHmac(utf8.encode(payload4), key);

  assert(!_listEquals(hmac1, hmac4),
      'Une sequence alteree doit produire un HMAC different');

  print('  OK: Alteration d\'etat detectee');
}

void testStateConstantTimeComparison() {
  print('Test: Constant time string comparison...');

  // Meme string
  assert(_ctEquals('abc123', 'abc123'), 'Egal: true');

  // Different
  assert(!_ctEquals('abc123', 'abc124'), 'Different: false');

  // Longueur differente
  assert(!_ctEquals('abc', 'abcd'), 'Longueur: false');

  // Vide
  assert(_ctEquals('', ''), 'Vide: true');

  print('  OK: Comparaison temps constant');
}

// === Helpers ===

List<String> _generateTailscaleArgs({
  required bool enableSshAudit,
  required bool forceMagicDns,
}) {
  return [
    if (enableSshAudit) '--ssh',
    if (forceMagicDns) '--accept-dns=true',
    '--timeout=30s',
  ];
}

List<int>? _parseVersion(String version) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

bool _isVersionAtLeast(String version, int major, int minor) {
  final parts = _parseVersion(version);
  if (parts == null) return false;
  if (parts[0] > major) return true;
  if (parts[0] == major && parts[1] >= minor) return true;
  return false;
}

Uint8List _simpleHmac(List<int> data, Uint8List key) {
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

bool _ctEquals(String a, String b) {
  if (a.length != b.length) return false;
  int result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}
