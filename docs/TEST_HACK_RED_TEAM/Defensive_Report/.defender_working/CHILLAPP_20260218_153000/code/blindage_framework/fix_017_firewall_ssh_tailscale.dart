// =============================================================
// FIX-017 : Firewall SSH restreint aux IPs Tailscale
// GAP-017: Firewall SSH non restreint aux IPs Tailscale
// Cible: lib/features/security/security_commands.dart (extension)
// =============================================================
//
// PROBLEME : Le port SSH est ouvert a toutes les IPs. N'importe
// qui sur le reseau local peut tenter une connexion SSH.
//
// SOLUTION : Regles firewall autorisant SSH uniquement depuis
// le reseau Tailscale (100.64.0.0/10) sur chaque OS.
// =============================================================

import 'dart:io';

/// Generateur de regles firewall restreignant SSH a Tailscale.
class TailscaleFirewallRules {
  /// Plage d'adresses CGNAT Tailscale.
  static const String tailscaleSubnet = '100.64.0.0/10';

  /// Port SSH cible (par defaut 22).
  final int sshPort;

  TailscaleFirewallRules({this.sshPort = 22});

  /// Applique les regles firewall SSH → Tailscale uniquement.
  /// Retourne true si les regles ont ete appliquees.
  Future<bool> applyRules() async {
    if (Platform.isLinux) return _applyLinux();
    if (Platform.isMacOS) return _applyMacOS();
    if (Platform.isWindows) return _applyWindows();
    return false;
  }

  /// Supprime les regles firewall SSH Tailscale.
  Future<bool> removeRules() async {
    if (Platform.isLinux) return _removeLinux();
    if (Platform.isMacOS) return _removeMacOS();
    if (Platform.isWindows) return _removeWindows();
    return false;
  }

  /// Verifie si les regles sont actives.
  Future<bool> checkRules() async {
    if (Platform.isLinux) return _checkLinux();
    if (Platform.isMacOS) return _checkMacOS();
    if (Platform.isWindows) return _checkWindows();
    return false;
  }

  // ===== LINUX (nftables) =====

  /// Script nftables pour Linux.
  String get _nftablesScript => '''
#!/usr/sbin/nft -f
# ChillApp - SSH restreint a Tailscale uniquement
# Installe dans /etc/nftables.d/chillapp-ssh.nft

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
    final script = File('${tempDir.path}/apply.sh');
    await script.writeAsString('''#!/bin/bash
# Creer le dossier si necessaire
mkdir -p /etc/nftables.d

# Ecrire les regles
cat > /etc/nftables.d/chillapp-ssh.nft << 'RULES'
$_nftablesScript
RULES

# Appliquer
nft -f /etc/nftables.d/chillapp-ssh.nft 2>/dev/null

# Si nft echoue, essayer ufw
if [ \$? -ne 0 ]; then
  # Fallback UFW
  ufw delete allow $sshPort/tcp 2>/dev/null
  ufw allow from $tailscaleSubnet to any port $sshPort proto tcp 2>/dev/null
  ufw deny $sshPort/tcp 2>/dev/null
fi

exit 0
''');
    await Process.run('chmod', ['700', script.path]);

    try {
      final result = await Process.run('pkexec', ['bash', script.path]);
      return result.exitCode == 0;
    } finally {
      try { await tempDir.delete(recursive: true); } catch (_) {}
    }
  }

  Future<bool> _removeLinux() async {
    final result = await Process.run('pkexec', [
      'bash', '-c',
      'nft delete table inet chillapp_ssh 2>/dev/null; '
      'rm -f /etc/nftables.d/chillapp-ssh.nft; '
      'ufw delete allow from $tailscaleSubnet to any port $sshPort proto tcp 2>/dev/null; '
      'ufw delete deny $sshPort/tcp 2>/dev/null; '
      'ufw allow $sshPort/tcp 2>/dev/null; '
      'exit 0',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _checkLinux() async {
    // Verifier nftables
    final nft = await Process.run('bash', [
      '-c', 'nft list table inet chillapp_ssh 2>/dev/null',
    ]);
    if (nft.exitCode == 0 &&
        nft.stdout.toString().contains(tailscaleSubnet)) {
      return true;
    }
    // Verifier UFW
    final ufw = await Process.run('bash', [
      '-c', 'ufw status 2>/dev/null',
    ]);
    return ufw.stdout.toString().contains(tailscaleSubnet);
  }

  // ===== MACOS (pf) =====

  Future<bool> _applyMacOS() async {
    final rules = '''
# ChillApp - SSH restreint a Tailscale
# Ajoute dans /etc/pf.anchors/chillapp
pass in on any proto tcp from $tailscaleSubnet to any port $sshPort
block in on any proto tcp from any to any port $sshPort
''';

    final tempDir = await Directory.systemTemp.createTemp('chill-fw-');
    final rulesFile = File('${tempDir.path}/chillapp');
    await rulesFile.writeAsString(rules);

    try {
      final result = await Process.run('osascript', [
        '-e',
        'do shell script "cp ${rulesFile.path} /etc/pf.anchors/chillapp && '
            'grep -q chillapp /etc/pf.conf || '
            'echo \\"anchor \\\\\\"chillapp\\\\\\"\\nload anchor \\\\\\"chillapp\\\\\\" '
            'from \\\\\\"/etc/pf.anchors/chillapp\\\\\\"\\" >> /etc/pf.conf && '
            'pfctl -f /etc/pf.conf" with administrator privileges',
      ]);
      return result.exitCode == 0;
    } finally {
      try { await tempDir.delete(recursive: true); } catch (_) {}
    }
  }

  Future<bool> _removeMacOS() async {
    final result = await Process.run('osascript', [
      '-e',
      'do shell script "rm -f /etc/pf.anchors/chillapp && '
          'sed -i \'\' \'/chillapp/d\' /etc/pf.conf && '
          'pfctl -f /etc/pf.conf" with administrator privileges',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _checkMacOS() async {
    final result = await Process.run('pfctl', ['-a', 'chillapp', '-sr']);
    return result.exitCode == 0 &&
        result.stdout.toString().contains(tailscaleSubnet);
  }

  // ===== WINDOWS (PowerShell) =====

  Future<bool> _applyWindows() async {
    final script = '''
# Supprimer les anciennes regles ChillApp
Remove-NetFirewallRule -DisplayName "ChillApp-SSH-*" -ErrorAction SilentlyContinue

# Autoriser SSH depuis Tailscale uniquement
New-NetFirewallRule -DisplayName "ChillApp-SSH-Allow-Tailscale" `
  -Direction Inbound -Protocol TCP -LocalPort $sshPort `
  -RemoteAddress $tailscaleSubnet -Action Allow

# Bloquer SSH de toute autre source
New-NetFirewallRule -DisplayName "ChillApp-SSH-Block-Others" `
  -Direction Inbound -Protocol TCP -LocalPort $sshPort `
  -Action Block
''';

    final result = await Process.run('powershell', [
      '-Command',
      'Start-Process powershell -Verb RunAs -Wait -ArgumentList '
          '"-Command $script"',
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
      'Get-NetFirewallRule -DisplayName "ChillApp-SSH-Allow-Tailscale" '
          '-ErrorAction SilentlyContinue | Measure-Object | '
          'Select-Object -ExpandProperty Count',
    ]);
    return result.exitCode == 0 &&
        (int.tryParse(result.stdout.toString().trim()) ?? 0) > 0;
  }
}

// =============================================================
// INTEGRATION dans security_commands.dart :
// =============================================================
//
// 1. Ajouter ces methodes dans SecurityCommands :
//
//    static Future<bool> applyTailscaleSshFirewall() async {
//      final rules = TailscaleFirewallRules();
//      return rules.applyRules();
//    }
//
//    static Future<bool> removeTailscaleSshFirewall() async {
//      final rules = TailscaleFirewallRules();
//      return rules.removeRules();
//    }
//
//    static Future<bool> checkTailscaleSshFirewall() async {
//      final rules = TailscaleFirewallRules();
//      return rules.checkRules();
//    }
//
// 2. Ajouter un toggle dans security_screen.dart pour cette regle.
// =============================================================
