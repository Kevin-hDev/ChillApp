// =============================================================
// FIX-017 : Regles de pare-feu SSH restreintes a Tailscale
// GAP-017 : Pare-feu SSH non restreint aux IPs Tailscale
// Cible  : lib/core/security/tailscale_firewall.dart (nouveau)
// =============================================================
//
// PROBLEME : Le port SSH est ouvert a toutes les adresses IP.
// N'importe qui sur le reseau local ou internet peut tenter
// de se connecter en SSH.
//
// SOLUTION : Appliquer des regles de pare-feu qui autorisent
// les connexions SSH (port 22 par defaut) uniquement depuis
// le reseau Tailscale (100.64.0.0/10) sur chaque OS.
//
//   Linux   : nftables (/etc/nftables.d/) avec fallback UFW
//   macOS   : pf anchor (/etc/pf.anchors/chillapp)
//   Windows : PowerShell NetFirewallRule
// =============================================================

import 'dart:io';
import 'dart:developer' as developer;

/// Applique, supprime et verifie les regles de pare-feu
/// qui restreignent SSH aux connexions Tailscale uniquement.
class TailscaleFirewallRules {
  /// Plage d'adresses CGNAT reservee a Tailscale.
  static const String tailscaleSubnet = '100.64.0.0/10';

  /// Port SSH protege (par defaut : 22).
  final int sshPort;

  /// Nom utilise pour identifier les regles dans chaque pare-feu.
  static const String _ruleTag = 'chillapp-ssh';

  TailscaleFirewallRules({this.sshPort = 22}) {
    // Validation de base : le port SSH doit etre valide
    assert(sshPort > 0 && sshPort <= 65535, 'Port SSH invalide: $sshPort');
  }

  // -----------------------------------------------------------------
  // API publique
  // -----------------------------------------------------------------

  /// Applique les regles de pare-feu sur l'OS courant.
  ///
  /// Retourne [true] si les regles ont ete appliquees avec succes.
  Future<bool> applyRules() async {
    try {
      if (Platform.isLinux) return await _applyLinux();
      if (Platform.isMacOS) return await _applyMacOS();
      if (Platform.isWindows) return await _applyWindows();
    } catch (e) {
      developer.log('Erreur: $e', name: 'TailscaleFirewall');
    }
    return false;
  }

  /// Supprime les regles de pare-feu appliquees par cette classe.
  ///
  /// Retourne [true] si les regles ont ete supprimees avec succes.
  Future<bool> removeRules() async {
    try {
      if (Platform.isLinux) return await _removeLinux();
      if (Platform.isMacOS) return await _removeMacOS();
      if (Platform.isWindows) return await _removeWindows();
    } catch (e) {
      developer.log('Erreur removeRules: $e', name: 'TailscaleFirewall');
    }
    return false;
  }

  /// Verifie si les regles de pare-feu sont actuellement actives.
  ///
  /// Retourne [true] si les regles Tailscale SSH sont en place.
  Future<bool> checkRules() async {
    try {
      if (Platform.isLinux) return await _checkLinux();
      if (Platform.isMacOS) return await _checkMacOS();
      if (Platform.isWindows) return await _checkWindows();
    } catch (e) {
      developer.log('Erreur checkRules: $e', name: 'TailscaleFirewall');
    }
    return false;
  }

  // -----------------------------------------------------------------
  // Linux — nftables avec fallback UFW
  // -----------------------------------------------------------------

  /// Contenu du fichier de regles nftables.
  String get _nftablesScript => '''
#!/usr/sbin/nft -f
# ChillApp — SSH restreint a Tailscale uniquement
# Installe dans /etc/nftables.d/$_ruleTag.nft

table inet chillapp_ssh {
  chain input {
    type filter hook input priority filter; policy accept;

    # Autoriser SSH depuis Tailscale (100.64.0.0/10) uniquement
    tcp dport $sshPort ip saddr $tailscaleSubnet accept

    # Bloquer SSH depuis toute autre source
    tcp dport $sshPort drop
  }
}
''';

  Future<bool> _applyLinux() async {
    final tempDir = await Directory.systemTemp.createTemp('chill-fw-');
    try {
      final scriptFile = File('${tempDir.path}/apply.sh');
      await scriptFile.writeAsString(_buildLinuxApplyScript());

      final chmodResult = await Process.run('chmod', ['700', scriptFile.path]);
      if (chmodResult.exitCode != 0) return false;

      final result = await Process.run('pkexec', ['bash', scriptFile.path]);
      return result.exitCode == 0;
    } finally {
      _deleteQuietly(tempDir);
    }
  }

  String _buildLinuxApplyScript() {
    return '''#!/bin/bash
set -e

# Creer le dossier nftables si necessaire
mkdir -p /etc/nftables.d

# Ecrire les regles nftables
cat > /etc/nftables.d/$_ruleTag.nft << 'RULES'
$_nftablesScript
RULES

# Appliquer les regles nftables
if nft -f /etc/nftables.d/$_ruleTag.nft 2>/dev/null; then
  echo "nftables OK"
else
  # Fallback : utiliser UFW si nftables echoue
  ufw delete allow $sshPort/tcp 2>/dev/null || true
  ufw allow from $tailscaleSubnet to any port $sshPort proto tcp 2>/dev/null
  ufw deny $sshPort/tcp 2>/dev/null || true
fi

exit 0
''';
  }

  Future<bool> _removeLinux() async {
    final result = await Process.run('pkexec', [
      'bash',
      '-c',
      'nft delete table inet chillapp_ssh 2>/dev/null || true; '
          'rm -f /etc/nftables.d/$_ruleTag.nft; '
          'ufw delete allow from $tailscaleSubnet to any port $sshPort proto tcp 2>/dev/null || true; '
          'ufw delete deny $sshPort/tcp 2>/dev/null || true; '
          'ufw allow $sshPort/tcp 2>/dev/null || true; '
          'exit 0',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _checkLinux() async {
    // Verifier d'abord via nftables
    final nft = await Process.run(
      'bash',
      ['-c', 'nft list table inet chillapp_ssh 2>/dev/null'],
    );
    if (nft.exitCode == 0 &&
        nft.stdout.toString().contains(tailscaleSubnet)) {
      return true;
    }

    // Verifier via UFW
    final ufw = await Process.run(
      'bash',
      ['-c', 'ufw status 2>/dev/null'],
    );
    return ufw.stdout.toString().contains(tailscaleSubnet);
  }

  // -----------------------------------------------------------------
  // macOS — pf anchor
  // -----------------------------------------------------------------

  String get _pfRules => '''
# ChillApp — SSH restreint a Tailscale
# Installe dans /etc/pf.anchors/chillapp
pass in on any proto tcp from $tailscaleSubnet to any port $sshPort
block in on any proto tcp from any to any port $sshPort
''';

  Future<bool> _applyMacOS() async {
    final tempDir = await Directory.systemTemp.createTemp('chill-fw-');
    try {
      final rulesFile = File('${tempDir.path}/chillapp');
      await rulesFile.writeAsString(_pfRules);

      // Copier les regles, activer l'anchor pf et recharger
      // Quoter le chemin pour éviter les problèmes si le chemin
      // contient des espaces ou des caractères spéciaux
      final escapedPath = rulesFile.path.replaceAll("'", "'\\''");
      final result = await Process.run('osascript', [
        '-e',
        'do shell script '
            '"cp \'$escapedPath\' /etc/pf.anchors/chillapp && '
            'grep -q chillapp /etc/pf.conf || '
            'printf \'anchor \\"chillapp\\"\\nload anchor \\"chillapp\\" '
            'from \\"/etc/pf.anchors/chillapp\\"\\n\' >> /etc/pf.conf && '
            'pfctl -f /etc/pf.conf 2>/dev/null || true" '
            'with administrator privileges',
      ]);
      return result.exitCode == 0;
    } finally {
      _deleteQuietly(tempDir);
    }
  }

  Future<bool> _removeMacOS() async {
    final result = await Process.run('osascript', [
      '-e',
      'do shell script '
          '"rm -f /etc/pf.anchors/chillapp && '
          "sed -i '' '/chillapp/d' /etc/pf.conf && "
          'pfctl -f /etc/pf.conf 2>/dev/null || true" '
          'with administrator privileges',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _checkMacOS() async {
    final result = await Process.run('pfctl', ['-a', 'chillapp', '-sr']);
    return result.exitCode == 0 &&
        result.stdout.toString().contains(tailscaleSubnet);
  }

  // -----------------------------------------------------------------
  // Windows — PowerShell NetFirewallRule
  // -----------------------------------------------------------------

  static const String _winRuleAllow = 'ChillApp-SSH-Allow-Tailscale';
  static const String _winRuleBlock = 'ChillApp-SSH-Block-Others';

  Future<bool> _applyWindows() async {
    final psScript = '''
Remove-NetFirewallRule -DisplayName "ChillApp-SSH-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "$_winRuleAllow" `
  -Direction Inbound -Protocol TCP -LocalPort $sshPort `
  -RemoteAddress $tailscaleSubnet -Action Allow
New-NetFirewallRule -DisplayName "$_winRuleBlock" `
  -Direction Inbound -Protocol TCP -LocalPort $sshPort `
  -Action Block
''';

    final result = await Process.run('powershell', [
      '-Command',
      'Start-Process powershell -Verb RunAs -Wait -ArgumentList '
          '"-Command $psScript"',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _removeWindows() async {
    final result = await Process.run('powershell', [
      '-Command',
      'Start-Process powershell -Verb RunAs -Wait -ArgumentList '
          '"-Command Remove-NetFirewallRule -DisplayName \'ChillApp-SSH-*\' '
          '-ErrorAction SilentlyContinue"',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _checkWindows() async {
    final result = await Process.run('powershell', [
      '-Command',
      'Get-NetFirewallRule -DisplayName "$_winRuleAllow" '
          '-ErrorAction SilentlyContinue | '
          'Measure-Object | Select-Object -ExpandProperty Count',
    ]);
    return result.exitCode == 0 &&
        (int.tryParse(result.stdout.toString().trim()) ?? 0) > 0;
  }

  // -----------------------------------------------------------------
  // Utilitaires internes
  // -----------------------------------------------------------------

  /// Supprime un repertoire sans lever d'exception.
  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // -----------------------------------------------------------------
  // Utilitaires de validation (testables sans executer de commandes)
  // -----------------------------------------------------------------

  /// Verifie que [subnet] est une notation CIDR valide.
  /// Utilise en interne et exposee pour les tests.
  static bool isValidCidr(String subnet) {
    final parts = subnet.split('/');
    if (parts.length != 2) return false;

    final ipParts = parts[0].split('.');
    if (ipParts.length != 4) return false;
    for (final p in ipParts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }

    final prefix = int.tryParse(parts[1]);
    return prefix != null && prefix >= 0 && prefix <= 32;
  }

  /// Verifie que [port] est un numero de port TCP valide.
  static bool isValidPort(int port) => port > 0 && port <= 65535;

  /// Construit la commande nftables sans l'executer (pour les tests).
  String buildNftScript() => _nftablesScript;

  /// Construit le script shell Linux sans l'executer (pour les tests).
  String buildLinuxApplyScript() => _buildLinuxApplyScript();
}
