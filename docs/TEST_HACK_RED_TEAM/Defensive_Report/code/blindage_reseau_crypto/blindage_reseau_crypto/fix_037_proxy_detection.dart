// =============================================================
// FIX-037 : Detection proxy/VPN tiers
// GAP-037: Detection proxy/VPN tiers absente (P2)
// Cible: lib/core/security/proxy_detection.dart (nouveau)
// =============================================================
//
// PROBLEME : Un proxy MITM (Burp Suite, mitmproxy, Charles) ou
// un VPN non-Tailscale peut intercepter les communications sans
// etre detecte. L'app doit fonctionner UNIQUEMENT via Tailscale.
//
// SOLUTION :
// 1. Detecter les variables d'environnement proxy
// 2. Scanner les ports proxy locaux courants
// 3. Verifier la table de routage pour VPN tiers
// 4. Alerter l'utilisateur si un proxy est detecte
// =============================================================

import 'dart:io';
import 'dart:async';

/// Type de menace detectee.
enum ProxyThreat {
  /// Variable d'environnement proxy definie.
  envProxy,

  /// Proxy local detecte sur un port courant.
  localProxy,

  /// VPN non-Tailscale detecte.
  foreignVpn,

  /// Route suspecte dans la table de routage.
  suspiciousRoute,
}

/// Resultat d'une detection.
class ProxyDetectionResult {
  final ProxyThreat threat;
  final String detail;
  final String severity; // critical, warning

  const ProxyDetectionResult({
    required this.threat,
    required this.detail,
    required this.severity,
  });

  @override
  String toString() => '[${threat.name}] $detail';
}

/// Detecteur de proxy et VPN tiers.
class ProxyDetector {
  /// Ports proxy courants a scanner.
  static const List<int> _proxyPorts = [
    8080,  // Burp Suite default
    8081,  // Burp Suite alternate
    8082,  // Common proxy
    8083,  // Charles Proxy
    8888,  // Charles Proxy default
    8443,  // HTTPS proxy
    9090,  // mitmproxy default
    9091,  // mitmproxy alternate
    3128,  // Squid default
    1080,  // SOCKS5
    1081,  // SOCKS alternate
  ];

  /// Variables d'environnement proxy a verifier.
  static const List<String> _proxyEnvVars = [
    'http_proxy',
    'HTTP_PROXY',
    'https_proxy',
    'HTTPS_PROXY',
    'all_proxy',
    'ALL_PROXY',
    'ftp_proxy',
    'FTP_PROXY',
    'socks_proxy',
    'SOCKS_PROXY',
    'no_proxy',
    'NO_PROXY',
  ];

  /// Noms d'interfaces VPN connues.
  static const List<String> _vpnInterfacePatterns = [
    'tun',     // OpenVPN, WireGuard generique
    'tap',     // OpenVPN TAP mode
    'wg',      // WireGuard
    'ppp',     // PPP (VPN)
    'utun',    // macOS VPN
    'ipsec',   // IPsec
    'vpn',     // Generique
    'nord',    // NordVPN
    'proton',  // ProtonVPN
    'mullvad', // Mullvad
  ];

  /// Noms d'interfaces Tailscale (a exclure de la detection).
  static const List<String> _tailscaleInterfaces = [
    'tailscale',
    'ts',
  ];

  /// Execute toutes les detections.
  Future<List<ProxyDetectionResult>> runFullScan() async {
    final results = <ProxyDetectionResult>[];

    // 1. Variables d'environnement
    results.addAll(_checkEnvironment());

    // 2. Ports proxy locaux
    results.addAll(await _scanProxyPorts());

    // 3. Interfaces VPN
    results.addAll(await _checkVpnInterfaces());

    // 4. Table de routage
    results.addAll(await _checkRoutingTable());

    return results;
  }

  /// Verifie les variables d'environnement proxy.
  List<ProxyDetectionResult> _checkEnvironment() {
    final results = <ProxyDetectionResult>[];

    for (final envVar in _proxyEnvVars) {
      final value = Platform.environment[envVar];
      if (value != null && value.isNotEmpty) {
        // Ignorer no_proxy (c'est une exception list)
        if (envVar.toLowerCase() == 'no_proxy') continue;

        results.add(ProxyDetectionResult(
          threat: ProxyThreat.envProxy,
          detail: 'Variable $envVar definie: ${_sanitize(value)}',
          severity: 'critical',
        ));
      }
    }

    return results;
  }

  /// Scanne les ports proxy locaux.
  Future<List<ProxyDetectionResult>> _scanProxyPorts() async {
    final results = <ProxyDetectionResult>[];

    for (final port in _proxyPorts) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 500),
        );
        await socket.close();

        results.add(ProxyDetectionResult(
          threat: ProxyThreat.localProxy,
          detail: 'Port proxy $port ouvert sur localhost',
          severity: 'warning',
        ));
      } catch (_) {
        // Port ferme — OK
      }
    }

    return results;
  }

  /// Detecte les interfaces VPN non-Tailscale.
  Future<List<ProxyDetectionResult>> _checkVpnInterfaces() async {
    final results = <ProxyDetectionResult>[];

    try {
      final interfaces = await NetworkInterface.list();

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();

        // Ignorer Tailscale
        if (_tailscaleInterfaces.any((t) => name.contains(t))) continue;

        // Ignorer les interfaces standard
        if (name.startsWith('lo') || name.startsWith('eth') ||
            name.startsWith('en') || name.startsWith('wl') ||
            name.startsWith('docker') || name.startsWith('br-') ||
            name.startsWith('veth')) continue;

        // Verifier si c'est une interface VPN
        if (_vpnInterfacePatterns.any((p) => name.contains(p))) {
          results.add(ProxyDetectionResult(
            threat: ProxyThreat.foreignVpn,
            detail: 'Interface VPN non-Tailscale detectee: ${iface.name}',
            severity: 'warning',
          ));
        }
      }
    } catch (_) {
      // Impossible de lister les interfaces
    }

    return results;
  }

  /// Verifie la table de routage pour des routes suspectes.
  Future<List<ProxyDetectionResult>> _checkRoutingTable() async {
    final results = <ProxyDetectionResult>[];

    try {
      ProcessResult routeResult;

      if (Platform.isLinux) {
        routeResult = await Process.run('ip', ['route', 'show']);
      } else if (Platform.isMacOS) {
        routeResult = await Process.run('netstat', ['-rn']);
      } else if (Platform.isWindows) {
        routeResult = await Process.run('route', ['print']);
      } else {
        return results;
      }

      if (routeResult.exitCode != 0) return results;

      final output = routeResult.stdout.toString();
      final lines = output.split('\n');

      for (final line in lines) {
        final lower = line.toLowerCase();

        // Chercher des routes par defaut suspectes
        // (pas via l'interface normale)
        if (lower.contains('default') || lower.contains('0.0.0.0/0')) {
          // Verifier si la route passe par une interface VPN
          for (final vpnPattern in _vpnInterfacePatterns) {
            if (lower.contains(vpnPattern) &&
                !_tailscaleInterfaces.any((t) => lower.contains(t))) {
              results.add(ProxyDetectionResult(
                threat: ProxyThreat.suspiciousRoute,
                detail: 'Route par defaut via interface VPN: ${line.trim()}',
                severity: 'critical',
              ));
            }
          }
        }
      }
    } catch (_) {
      // Impossible de lire la table de routage
    }

    return results;
  }

  /// Sanitise une valeur pour le logging (masque les IPs et ports).
  String _sanitize(String value) {
    if (value.length > 50) {
      return '${value.substring(0, 50)}...';
    }
    return value;
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Au demarrage de l'app et periodiquement :
//
//   final detector = ProxyDetector();
//   final threats = await detector.runFullScan();
//
//   if (threats.isNotEmpty) {
//     final critical = threats.where((t) => t.severity == 'critical');
//     if (critical.isNotEmpty) {
//       // Bloquer la connexion (fail closed)
//       failGuard.forceOpen('Proxy/VPN detecte: ${critical.first}');
//       showProxyWarningDialog(critical.toList());
//     } else {
//       // Avertir l'utilisateur
//       showProxyInfoBanner(threats);
//     }
//   }
//
// Scanner periodique (toutes les 5 minutes) :
//   Timer.periodic(Duration(minutes: 5), (_) async {
//     final threats = await detector.runFullScan();
//     // ...
//   });
// =============================================================
