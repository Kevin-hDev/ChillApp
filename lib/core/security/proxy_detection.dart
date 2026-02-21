// =============================================================
// FIX-037 : Detection de proxy et VPN non-Tailscale
// GAP-037 : Absence de detection de proxy/VPN (P1)
// Cible  : lib/core/security/proxy_detection.dart (nouveau)
// =============================================================
//
// PROBLEME : Un proxy ou VPN non-Tailscale peut intercepter les
// communications SSH de ChillApp a l'insu de l'utilisateur,
// compromettant la confidentialite et l'integrite des echanges.
//
// SOLUTION : Scanner l'environnement pour detecter :
//   1. Variables d'environnement proxy (http_proxy, etc.)
//   2. Ports proxy ouverts sur localhost
//   3. Interfaces reseau de type VPN (non-Tailscale)
//   4. Routes suspectes dans la table de routage
// =============================================================

import 'dart:io';
import 'dart:async';

/// Nature de la menace detectee.
enum ProxyThreat {
  /// Variable d'environnement proxy definie.
  envProxy,

  /// Port proxy ecoute sur localhost.
  localProxy,

  /// Interface VPN non-Tailscale detectee.
  foreignVpn,

  /// Route par defaut passant par une interface VPN.
  suspiciousRoute,
}

/// Resultat d'une detection de proxy/VPN.
class ProxyDetectionResult {
  /// Nature de la menace.
  final ProxyThreat threat;

  /// Description lisible du probleme detecte.
  final String detail;

  /// Niveau de severite : 'critical' ou 'warning'.
  final String severity;

  const ProxyDetectionResult({
    required this.threat,
    required this.detail,
    required this.severity,
  });

  @override
  String toString() => '[${threat.name}] $detail';
}

/// Detecteur de proxy et VPN non-Tailscale.
///
/// Effectue quatre types de verification :
///   1. Variables d'environnement proxy
///   2. Ports proxy ouverts sur localhost
///   3. Interfaces reseau de type VPN (hors Tailscale)
///   4. Table de routage
class ProxyDetector {
  /// Ports typiquement utilises par des proxies locaux.
  static const List<int> proxyPorts = [
    8080, 8081, 8082, 8083, 8888, 8443,
    9090, 9091, 3128, 1080, 1081,
  ];

  /// Variables d'environnement standard pour la configuration proxy.
  static const List<String> proxyEnvVars = [
    'http_proxy', 'HTTP_PROXY', 'https_proxy', 'HTTPS_PROXY',
    'all_proxy', 'ALL_PROXY', 'ftp_proxy', 'FTP_PROXY',
    'socks_proxy', 'SOCKS_PROXY', 'no_proxy', 'NO_PROXY',
  ];

  /// Prefixes et mots-cles identifies comme interfaces VPN.
  static const List<String> vpnInterfacePatterns = [
    'tun', 'tap', 'wg', 'ppp', 'utun', 'ipsec',
    'vpn', 'nord', 'proton', 'mullvad',
  ];

  /// Prefixes Tailscale (exclus des alertes — VPN approuve).
  static const List<String> tailscaleInterfaces = ['tailscale', 'ts'];

  /// Lance l'analyse complete (toutes les verifications).
  ///
  /// Retourne la liste de toutes les menaces detectees.
  /// Une liste vide signifie qu'aucune menace n'a ete trouvee.
  Future<List<ProxyDetectionResult>> runFullScan() async {
    final results = <ProxyDetectionResult>[];
    results.addAll(checkEnvironment());
    results.addAll(await scanProxyPorts());
    results.addAll(await checkVpnInterfaces());
    results.addAll(await checkRoutingTable());
    return results;
  }

  /// Verifie les variables d'environnement proxy.
  ///
  /// Ignore NO_PROXY (liste d'exclusions, non dangereuse).
  List<ProxyDetectionResult> checkEnvironment() {
    final results = <ProxyDetectionResult>[];
    for (final envVar in proxyEnvVars) {
      final value = Platform.environment[envVar];
      if (value != null && value.isNotEmpty) {
        // NO_PROXY est une liste d'exclusions, pas un proxy actif
        if (envVar.toLowerCase() == 'no_proxy') continue;
        results.add(ProxyDetectionResult(
          threat: ProxyThreat.envProxy,
          detail: 'Variable $envVar definie: ${sanitize(value)}',
          severity: 'critical',
        ));
      }
    }
    return results;
  }

  /// Tente une connexion TCP sur chaque port proxy de [proxyPorts].
  ///
  /// Un port ouvert indique la presence d'un proxy local.
  Future<List<ProxyDetectionResult>> scanProxyPorts() async {
    final results = <ProxyDetectionResult>[];
    for (final port in proxyPorts) {
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
        // Port ferme ou connexion refusee — comportement attendu
      }
    }
    return results;
  }

  /// Examine les interfaces reseau pour detecter les VPN non-Tailscale.
  ///
  /// Les interfaces loopback (lo), Ethernet (eth/en), Wi-Fi (wl),
  /// Docker et veth sont ignorees comme inoffensives.
  Future<List<ProxyDetectionResult>> checkVpnInterfaces() async {
    final results = <ProxyDetectionResult>[];
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();

        // Ignorer les interfaces Tailscale approuvees
        if (tailscaleInterfaces.any((t) => name.contains(t))) {
          continue;
        }

        // Ignorer les interfaces systeme courantes inoffensives
        if (name.startsWith('lo') ||
            name.startsWith('eth') ||
            name.startsWith('en') ||
            name.startsWith('wl') ||
            name.startsWith('docker') ||
            name.startsWith('br-') ||
            name.startsWith('veth')) {
          continue;
        }

        // Verifier si le nom correspond a un pattern VPN connu
        if (vpnInterfacePatterns.any((p) => name.contains(p))) {
          results.add(ProxyDetectionResult(
            threat: ProxyThreat.foreignVpn,
            detail: 'Interface VPN non-Tailscale detectee: ${iface.name}',
            severity: 'warning',
          ));
        }
      }
    } catch (_) {
      // Impossibilite de lister les interfaces — ignorer
    }
    return results;
  }

  /// Analyse la table de routage pour detecter une route par defaut
  /// passant par une interface VPN non-Tailscale.
  Future<List<ProxyDetectionResult>> checkRoutingTable() async {
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

      final lines = routeResult.stdout.toString().split('\n');
      for (final line in lines) {
        final lower = line.toLowerCase();
        // Chercher les lignes de route par defaut
        if (lower.contains('default') || lower.contains('0.0.0.0/0')) {
          for (final vpnPattern in vpnInterfacePatterns) {
            if (lower.contains(vpnPattern) &&
                !tailscaleInterfaces.any((t) => lower.contains(t))) {
              results.add(ProxyDetectionResult(
                threat: ProxyThreat.suspiciousRoute,
                detail:
                    'Route par defaut via interface VPN: ${line.trim()}',
                severity: 'critical',
              ));
            }
          }
        }
      }
    } catch (_) {
      // Commande indisponible sur cet OS — ignorer
    }
    return results;
  }

  /// Tronque une valeur longue pour eviter les logs excessifs.
  ///
  /// Methode publique et statique pour faciliter les tests.
  /// Toute valeur superieure a 50 caracteres est tronquee.
  static String sanitize(String value) {
    if (value.length > 50) return '${value.substring(0, 50)}...';
    return value;
  }
}
