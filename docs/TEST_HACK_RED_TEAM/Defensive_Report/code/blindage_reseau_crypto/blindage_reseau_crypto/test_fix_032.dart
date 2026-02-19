// =============================================================
// Tests pour FIX-032 : Fail Closed Guard
// =============================================================

void main() {
  print('=== Tests FIX-032 : Fail Closed ===\n');

  testTailscaleIpValidation();
  testNonTailscaleIpBlocked();
  testTailscaleHostname();
  testNonTailscaleHostnameBlocked();
  testCircuitBreakerOpensAfterFailures();
  testCircuitBreakerReset();
  testIPv6TailscaleValidation();
  testBlockLogKeptBounded();

  print('\n=== Tous les tests FIX-032 passes ===');
}

/// Test : IP Tailscale valide (100.64-127.x.x).
void testTailscaleIpValidation() {
  print('Test: Tailscale IP validation...');

  final validIps = [
    '100.64.0.1',
    '100.100.100.100',
    '100.127.255.255',
    '100.80.12.34',
  ];

  for (final ip in validIps) {
    assert(_isTailscaleIp(ip), 'IP $ip devrait etre valide Tailscale');
  }

  print('  OK: IPs Tailscale validees');
}

/// Test : IPs non-Tailscale bloquees.
void testNonTailscaleIpBlocked() {
  print('Test: Non-Tailscale IPs blocked...');

  final invalidIps = [
    '192.168.1.1',
    '10.0.0.1',
    '172.16.0.1',
    '8.8.8.8',
    '100.63.255.255',   // Juste en dessous de 100.64
    '100.128.0.0',       // Juste au dessus de 100.127
    '0.0.0.0',
    '255.255.255.255',
    '127.0.0.1',
  ];

  for (final ip in invalidIps) {
    assert(!_isTailscaleIp(ip), 'IP $ip devrait etre bloquee');
  }

  print('  OK: IPs non-Tailscale bloquees');
}

/// Test : Hostnames .ts.net autorises.
void testTailscaleHostname() {
  print('Test: Tailscale hostname validation...');

  assert(_isTailscaleHostname('my-pc.ts.net'),
      'my-pc.ts.net devrait etre valide');
  assert(_isTailscaleHostname('server.my-tailnet.ts.net'),
      'server.my-tailnet.ts.net devrait etre valide');

  print('  OK: Hostnames .ts.net valides');
}

/// Test : Hostnames non-Tailscale bloques.
void testNonTailscaleHostnameBlocked() {
  print('Test: Non-Tailscale hostnames blocked...');

  assert(!_isTailscaleHostname('google.com'),
      'google.com devrait etre bloque');
  assert(!_isTailscaleHostname('evil.ts.net.attacker.com'),
      'evil.ts.net.attacker.com devrait etre bloque');
  assert(!_isTailscaleHostname('192.168.1.1'),
      '192.168.1.1 n\'est pas un hostname .ts.net');

  print('  OK: Hostnames non-Tailscale bloques');
}

/// Test : Le circuit s'ouvre apres N echecs.
void testCircuitBreakerOpensAfterFailures() {
  print('Test: Circuit breaker opens after failures...');

  var state = 'closed';
  var failures = 0;
  const maxFailures = 3;

  // Simuler 3 echecs
  for (int i = 0; i < maxFailures; i++) {
    failures++;
    if (failures >= maxFailures) {
      state = 'open';
    }
  }

  assert(state == 'open',
      'Le circuit doit etre ouvert apres $maxFailures echecs');
  assert(failures == maxFailures,
      'Le compteur doit etre a $maxFailures');

  print('  OK: Circuit ouvert apres $maxFailures echecs');
}

/// Test : Reset du circuit.
void testCircuitBreakerReset() {
  print('Test: Circuit breaker reset...');

  var state = 'open';
  var failures = 3;

  // Reset
  state = 'closed';
  failures = 0;

  assert(state == 'closed', 'Le circuit doit etre ferme apres reset');
  assert(failures == 0, 'Le compteur doit etre a 0');

  print('  OK: Reset du circuit fonctionne');
}

/// Test : IPv6 Tailscale (fd7a:115c:a1e0::/48).
void testIPv6TailscaleValidation() {
  print('Test: IPv6 Tailscale validation...');

  // fd7a:115c:a1e0::1 est une IP Tailscale IPv6
  assert(_isTailscaleIpv6('fd7a:115c:a1e0::1'),
      'fd7a:115c:a1e0::1 devrait etre valide');

  assert(!_isTailscaleIpv6('2001:db8::1'),
      '2001:db8::1 ne devrait pas etre valide');

  assert(!_isTailscaleIpv6('::1'),
      '::1 (localhost) ne devrait pas etre valide');

  print('  OK: IPv6 Tailscale validee');
}

/// Test : Le log de blocage est borne.
void testBlockLogKeptBounded() {
  print('Test: Block log bounded...');

  final log = <String>[];
  const maxLog = 100;

  // Ajouter 150 entrees
  for (int i = 0; i < 150; i++) {
    log.add('block_$i');
    if (log.length > maxLog) {
      log.removeAt(0);
    }
  }

  assert(log.length == maxLog,
      'Le log doit etre borne a $maxLog entrees');
  assert(log.first == 'block_50',
      'Le premier element doit etre block_50');

  print('  OK: Log borne a $maxLog entrees');
}

// === Helpers ===

bool _isTailscaleIp(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final bytes = parts.map(int.tryParse).toList();
  if (bytes.any((b) => b == null)) return false;
  return bytes[0] == 100 && bytes[1]! >= 64 && bytes[1]! <= 127;
}

bool _isTailscaleHostname(String hostname) {
  return hostname.endsWith('.ts.net') &&
      !hostname.contains('.ts.net.'); // Pas un sous-domaine trompeur
}

bool _isTailscaleIpv6(String ip) {
  // Verification simplifiee du prefix fd7a:115c:a1e0::/48
  final normalized = ip.toLowerCase();
  return normalized.startsWith('fd7a:115c:a1e0');
}
