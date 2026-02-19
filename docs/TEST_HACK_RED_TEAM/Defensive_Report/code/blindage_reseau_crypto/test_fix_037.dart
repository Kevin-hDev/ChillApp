// =============================================================
// Tests pour FIX-037 : Detection proxy/VPN
// =============================================================

import 'dart:io';

void main() {
  print('=== Tests FIX-037 : Proxy Detection ===\n');

  testProxyEnvVarDetection();
  testProxyPortList();
  testVpnInterfacePatterns();
  testTailscaleInterfaceExcluded();
  testStandardInterfaceExcluded();
  testSanitization();

  print('\n=== Tous les tests FIX-037 passes ===');
}

void testProxyEnvVarDetection() {
  print('Test: Proxy env var detection...');

  final proxyVars = [
    'http_proxy', 'HTTP_PROXY',
    'https_proxy', 'HTTPS_PROXY',
    'all_proxy', 'ALL_PROXY',
    'ftp_proxy', 'FTP_PROXY',
    'socks_proxy', 'SOCKS_PROXY',
  ];

  // Verifier que toutes les variables sont dans notre liste
  for (final v in proxyVars) {
    assert(_isProxyEnvVar(v), '$v devrait etre detecte comme proxy env var');
  }

  // no_proxy est special (liste d'exclusion, pas un proxy)
  // Il ne devrait pas declencher une alerte
  assert(!_shouldAlertForEnvVar('no_proxy'),
      'no_proxy ne devrait pas declencher d\'alerte');
  assert(!_shouldAlertForEnvVar('NO_PROXY'),
      'NO_PROXY ne devrait pas declencher d\'alerte');

  print('  OK: Variables proxy detectees, no_proxy ignore');
}

void testProxyPortList() {
  print('Test: Proxy port list...');

  final proxyPorts = [
    8080,  // Burp Suite
    8081,  // Burp alternate
    8888,  // Charles Proxy
    9090,  // mitmproxy
    3128,  // Squid
    1080,  // SOCKS5
  ];

  // Verifier que les ports courants sont dans la liste
  for (final port in proxyPorts) {
    assert(_knownProxyPorts.contains(port),
        'Port $port devrait etre dans la liste des ports proxy');
  }

  // Des ports normaux ne sont pas dans la liste
  assert(!_knownProxyPorts.contains(80), 'Port 80 n\'est pas un proxy');
  assert(!_knownProxyPorts.contains(443), 'Port 443 n\'est pas un proxy');
  assert(!_knownProxyPorts.contains(22), 'Port 22 n\'est pas un proxy');

  print('  OK: Ports proxy corrects');
}

void testVpnInterfacePatterns() {
  print('Test: VPN interface patterns...');

  final vpnInterfaces = [
    'tun0', 'tun1', 'tap0',
    'wg0', 'wg1',
    'ppp0',
    'utun3',
    'nordlynx',
    'proton0',
    'mullvad-tun',
  ];

  for (final iface in vpnInterfaces) {
    assert(_isVpnInterface(iface),
        'Interface $iface devrait etre detectee comme VPN');
  }

  print('  OK: Interfaces VPN detectees');
}

void testTailscaleInterfaceExcluded() {
  print('Test: Tailscale interface excluded...');

  final tailscaleInterfaces = [
    'tailscale0',
    'ts0',
  ];

  for (final iface in tailscaleInterfaces) {
    assert(_isTailscaleInterface(iface),
        'Interface $iface devrait etre reconnue comme Tailscale');
  }

  print('  OK: Interfaces Tailscale exclues de la detection');
}

void testStandardInterfaceExcluded() {
  print('Test: Standard interfaces excluded...');

  final standardInterfaces = [
    'lo', 'lo0',
    'eth0', 'eth1',
    'en0', 'en1',
    'wlan0', 'wlp2s0',
    'docker0',
    'br-abc123',
    'veth123abc',
  ];

  for (final iface in standardInterfaces) {
    assert(_isStandardInterface(iface),
        'Interface $iface devrait etre reconnue comme standard');
  }

  print('  OK: Interfaces standard exclues');
}

void testSanitization() {
  print('Test: Sanitization...');

  // Les URLs proxy ne doivent pas etre loguees en entier
  final longUrl = 'http://user:password@proxy.evil.com:8080/path?token=secret123456';
  final sanitized = _sanitize(longUrl);

  assert(sanitized.length <= 53,
      'URL sanitisee trop longue (${sanitized.length})');

  print('  OK: Sanitisation des URLs proxy');
}

// === Helpers reproduisant la logique ===

const _knownProxyPorts = [
  8080, 8081, 8082, 8083, 8888, 8443, 9090, 9091, 3128, 1080, 1081,
];

const _proxyEnvVarNames = [
  'http_proxy', 'HTTP_PROXY',
  'https_proxy', 'HTTPS_PROXY',
  'all_proxy', 'ALL_PROXY',
  'ftp_proxy', 'FTP_PROXY',
  'socks_proxy', 'SOCKS_PROXY',
  'no_proxy', 'NO_PROXY',
];

const _vpnPatterns = [
  'tun', 'tap', 'wg', 'ppp', 'utun', 'ipsec',
  'vpn', 'nord', 'proton', 'mullvad',
];

const _tailscalePatterns = ['tailscale', 'ts'];

bool _isProxyEnvVar(String name) {
  return _proxyEnvVarNames.contains(name);
}

bool _shouldAlertForEnvVar(String name) {
  if (name.toLowerCase() == 'no_proxy') return false;
  return _proxyEnvVarNames.contains(name);
}

bool _isVpnInterface(String name) {
  final lower = name.toLowerCase();
  // D'abord exclure Tailscale
  if (_isTailscaleInterface(name)) return false;
  return _vpnPatterns.any((p) => lower.contains(p));
}

bool _isTailscaleInterface(String name) {
  final lower = name.toLowerCase();
  return _tailscalePatterns.any((p) => lower.contains(p));
}

bool _isStandardInterface(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('lo') || lower.startsWith('eth') ||
      lower.startsWith('en') || lower.startsWith('wl') ||
      lower.startsWith('docker') || lower.startsWith('br-') ||
      lower.startsWith('veth');
}

String _sanitize(String value) {
  if (value.length > 50) return '${value.substring(0, 50)}...';
  return value;
}
