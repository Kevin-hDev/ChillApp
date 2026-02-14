import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

/// Commandes de sécurité par OS.
/// Chaque toggle a 3 méthodes : check, enable, disable.
class SecurityCommands {
  // ============================================
  // WINDOWS
  // ============================================

  // --- Firewall ---
  static Future<bool?> checkWindowsFirewall() async {
    final result = await CommandRunner.runPowerShell(
      'Get-NetFirewallProfile | Select-Object -ExpandProperty Enabled',
    );
    if (!result.success) return null;
    return !result.stdout.contains('False');
  }

  static Future<bool> enableWindowsFirewall() async {
    final result = await CommandRunner.runPowerShell(
      'Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True',
    );
    return result.success;
  }

  static Future<bool> disableWindowsFirewall() async {
    final result = await CommandRunner.runPowerShell(
      'Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False',
    );
    return result.success;
  }

  // --- Remote Desktop (inversé : true = désactivé = sécurisé) ---
  static Future<bool?> checkWindowsRdp() async {
    final result = await CommandRunner.runPowerShell(
      "Get-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' | Select-Object -ExpandProperty fDenyTSConnections",
    );
    if (!result.success) return null;
    return result.stdout.trim() == '1'; // 1 = désactivé = sécurisé
  }

  static Future<bool> enableWindowsRdpProtection() async {
    final result = await CommandRunner.runPowerShell(
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 1",
    );
    return result.success;
  }

  static Future<bool> disableWindowsRdpProtection() async {
    final result = await CommandRunner.runPowerShell(
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
    );
    return result.success;
  }

  // --- SMBv1 (inversé : true = désactivé = sécurisé) ---
  static Future<bool?> checkWindowsSmb1() async {
    final result = await CommandRunner.runPowerShell(
      'Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol | Select-Object -ExpandProperty State',
    );
    if (!result.success) return null;
    return result.stdout.trim() == 'Disabled'; // Disabled = sécurisé
  }

  static Future<bool> enableWindowsSmb1Protection() async {
    final result = await CommandRunner.runPowerShell(
      'Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart',
    );
    return result.success;
  }

  static Future<bool> disableWindowsSmb1Protection() async {
    final result = await CommandRunner.runPowerShell(
      'Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart',
    );
    return result.success;
  }

  // --- Remote Registry (inversé : true = désactivé = sécurisé) ---
  static Future<bool?> checkWindowsRemoteRegistry() async {
    final result = await CommandRunner.runPowerShell(
      "Get-Service RemoteRegistry | Select-Object -ExpandProperty StartType",
    );
    if (!result.success) return null;
    return result.stdout.trim() == 'Disabled';
  }

  static Future<bool> enableWindowsRemoteRegistryProtection() async {
    final result = await CommandRunner.runPowerShell(
      'Stop-Service RemoteRegistry -Force -ErrorAction SilentlyContinue; Set-Service RemoteRegistry -StartupType Disabled',
    );
    return result.success;
  }

  static Future<bool> disableWindowsRemoteRegistryProtection() async {
    final result = await CommandRunner.runPowerShell(
      'Set-Service RemoteRegistry -StartupType Manual; Start-Service RemoteRegistry',
    );
    return result.success;
  }

  // --- Anti-ransomware (Controlled Folder Access) ---
  static Future<bool?> checkWindowsRansomware() async {
    final result = await CommandRunner.runPowerShell(
      'Get-MpPreference | Select-Object -ExpandProperty EnableControlledFolderAccess',
    );
    if (!result.success) return null;
    return result.stdout.trim() == '1';
  }

  static Future<bool> enableWindowsRansomware() async {
    final result = await CommandRunner.runPowerShell(
      'Set-MpPreference -EnableControlledFolderAccess Enabled',
    );
    return result.success;
  }

  static Future<bool> disableWindowsRansomware() async {
    final result = await CommandRunner.runPowerShell(
      'Set-MpPreference -EnableControlledFolderAccess Disabled',
    );
    return result.success;
  }

  // --- Audit des connexions ---
  // Utilise le GUID au lieu du nom localisé ("Logon" en EN, "Ouvrir la session" en FR)
  static const _auditLogonGuid = '{0CCE9215-69AE-11D9-BED3-505054503030}';

  static Future<bool?> checkWindowsAudit() async {
    // La comparaison de texte se fait DANS PowerShell pour éviter les
    // problèmes d'encodage des accents (é, è) entre PowerShell et Dart.
    // On ne sort que du ASCII simple : TRUE, FALSE ou ERROR.
    final result = await CommandRunner.runPowerShell(
      "\$out = auditpol /get /subcategory:\"$_auditLogonGuid\" 2>&1 | Out-String; "
      "if (\$LASTEXITCODE -ne 0) { Write-Output 'ERROR' } "
      "elseif (\$out -match 'Success.*Failure|Succ.*chec') { Write-Output 'TRUE' } "
      "else { Write-Output 'FALSE' }",
    );
    if (!result.success) return null;
    final val = result.stdout.trim();
    if (val == 'ERROR') return null;
    return val == 'TRUE';
  }

  static Future<bool> enableWindowsAudit() async {
    final result = await CommandRunner.runPowerShell(
      'auditpol /set /subcategory:"$_auditLogonGuid" /success:enable /failure:enable',
    );
    return result.success;
  }

  static Future<bool> disableWindowsAudit() async {
    final result = await CommandRunner.runPowerShell(
      'auditpol /set /subcategory:"$_auditLogonGuid" /success:disable /failure:disable',
    );
    return result.success;
  }

  // --- Mises à jour auto ---
  // Vérifie les deux chemins possibles : Group Policy (prioritaire) puis standard
  static Future<bool?> checkWindowsUpdates() async {
    final result = await CommandRunner.runPowerShell(
      "\$gp = Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' "
      "-Name 'AUOptions' -ErrorAction SilentlyContinue; "
      "\$std = Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update' "
      "-Name 'AUOptions' -ErrorAction SilentlyContinue; "
      "if (\$gp -and \$gp.AUOptions -ne \$null) { Write-Output \$gp.AUOptions } "
      "elseif (\$std -and \$std.AUOptions -ne \$null) { Write-Output \$std.AUOptions } "
      "else { Write-Output 'DEFAULT' }",
    );
    if (!result.success) return null;
    final val = result.stdout.trim();
    // DEFAULT = pas de config explicite = Windows auto-update par défaut
    // 4 = téléchargement et installation automatiques
    return val == 'DEFAULT' || val == '4';
  }

  static Future<bool> enableWindowsUpdates() async {
    final result = await CommandRunner.runPowerShell(
      "New-Item -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Force -ErrorAction SilentlyContinue | Out-Null; "
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Name 'AUOptions' -Value 4 -Type DWord; "
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Name 'NoAutoUpdate' -Value 0 -Type DWord",
    );
    return result.success;
  }

  static Future<bool> disableWindowsUpdates() async {
    final result = await CommandRunner.runPowerShell(
      "New-Item -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Force -ErrorAction SilentlyContinue | Out-Null; "
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Name 'AUOptions' -Value 2 -Type DWord; "
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU' -Name 'NoAutoUpdate' -Value 0 -Type DWord",
    );
    return result.success;
  }

  // ============================================
  // LINUX
  // ============================================

  /// Helper : exécuter un script bash avec pkexec (un seul mot de passe)
  static Future<CommandResult> _runLinuxElevated(String script) async {
    final tempDir = await Directory.systemTemp.createTemp('chill-sec-');
    final tempScript = File('${tempDir.path}/security.sh');
    await tempScript.writeAsString(script);
    await Process.run('chmod', ['700', tempDir.path]);
    await Process.run('chmod', ['700', tempScript.path]);

    try {
      return await CommandRunner.runElevated('bash', [tempScript.path]);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        debugPrint('[Security] Cleanup error: $e');
      }
    }
  }

  // --- Firewall UFW ---
  static Future<bool?> checkLinuxFirewall() async {
    // Lire /etc/ufw/ufw.conf (lisible sans root) pour éviter le problème de permissions
    final result = await CommandRunner.run(
      'grep', ['-q', 'ENABLED=yes', '/etc/ufw/ufw.conf'],
    );
    if (result.success) return true;
    // Vérifier si ufw est installé
    final which = await CommandRunner.run('which', ['ufw']);
    if (!which.success) return null; // UFW pas installé
    return false;
  }

  static Future<bool> checkLinuxUfwInstalled() async {
    final result = await CommandRunner.run('which', ['ufw']);
    return result.success;
  }

  static Future<bool> installLinuxUfw() async {
    final distro = await OsDetector.detectLinuxDistro();
    String installCmd;
    switch (distro) {
      case LinuxDistro.debian:
        installCmd = 'apt update -qq && apt install ufw -y -qq';
        break;
      case LinuxDistro.fedora:
        installCmd = 'dnf install ufw -y -q';
        break;
      case LinuxDistro.arch:
        installCmd = 'pacman -S --noconfirm ufw';
        break;
      case LinuxDistro.unknown:
        return false;
    }
    final result = await _runLinuxElevated('#!/bin/bash\n$installCmd\nexit \$?\n');
    return result.success;
  }

  static Future<bool> enableLinuxFirewall() async {
    final script = '#!/bin/bash\n'
        'ufw default deny incoming\n'
        'ufw default allow outgoing\n'
        'ufw allow ssh\n'
        'ufw --force enable\n'
        'exit \$?\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  static Future<bool> disableLinuxFirewall() async {
    final result = await _runLinuxElevated('#!/bin/bash\nufw disable\nexit \$?\n');
    return result.success;
  }

  // --- Paramètres réseau sécurisés (sysctl) ---
  static Future<bool?> checkLinuxSysctl() async {
    final result = await CommandRunner.run('sysctl', [
      'net.ipv4.conf.all.accept_redirects',
    ]);
    if (!result.success) return null;
    return result.stdout.contains('= 0');
  }

  static Future<bool> enableLinuxSysctl() async {
    final script = '#!/bin/bash\n'
        'tee /etc/sysctl.d/99-hardening.conf > /dev/null <<EOF\n'
        'net.ipv4.conf.all.accept_redirects = 0\n'
        'net.ipv4.conf.all.send_redirects = 0\n'
        'net.ipv4.conf.all.accept_source_route = 0\n'
        'net.ipv4.conf.all.log_martians = 1\n'
        'net.ipv4.icmp_echo_ignore_broadcasts = 1\n'
        'EOF\n'
        'sysctl --system > /dev/null 2>&1\n'
        'exit 0\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  static Future<bool> disableLinuxSysctl() async {
    final script = '#!/bin/bash\n'
        'rm -f /etc/sysctl.d/99-hardening.conf\n'
        'sysctl --system > /dev/null 2>&1\n'
        'exit 0\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  // --- Services inutiles ---
  static Future<List<Map<String, dynamic>>> detectLinuxServices() async {
    final services = <Map<String, dynamic>>[];
    final candidates = [
      {'name': 'cups', 'display': 'CUPS (impression)'},
      {'name': 'avahi-daemon', 'display': 'Avahi (découverte réseau)'},
      {'name': 'bluetooth', 'display': 'Bluetooth'},
    ];

    for (final candidate in candidates) {
      final result = await CommandRunner.run(
        'systemctl',
        ['is-active', '--quiet', candidate['name']!],
      );
      // Le service existe si exit code est 0 (actif) ou 3 (inactif mais installé)
      final existsResult = await CommandRunner.run(
        'systemctl',
        ['cat', candidate['name']!],
      );
      if (existsResult.success) {
        services.add({
          'name': candidate['name']!,
          'display': candidate['display']!,
          'active': result.success,
        });
      }
    }
    return services;
  }

  static Future<bool> toggleLinuxService(String name, bool enable) async {
    final action = enable ? 'enable --now' : 'disable --now';
    // Échapper le nom du service pour éviter l'injection
    final safeName = name.replaceAll("'", "'\\''");
    final script = "#!/bin/bash\nsystemctl $action '$safeName'\nexit \$?\n";
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  // --- Permissions fichiers sensibles ---
  static Future<bool?> checkLinuxPermissions() async {
    final result = await CommandRunner.run('stat', [
      '-c',
      '%a',
      '/etc/shadow',
    ]);
    if (!result.success) return null;
    return result.stdout.trim() == '600';
  }

  static Future<bool> enableLinuxPermissions() async {
    final script = '#!/bin/bash\n'
        'chmod 600 /etc/shadow 2>/dev/null\n'
        'chmod 600 /etc/gshadow 2>/dev/null\n'
        'chmod 644 /etc/passwd\n'
        'chmod 700 /etc/ssh 2>/dev/null\n'
        'exit 0\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  // --- Fail2Ban ---
  static Future<bool> checkLinuxFail2banInstalled() async {
    final result = await CommandRunner.run('which', ['fail2ban-client']);
    return result.success;
  }

  static Future<bool?> checkLinuxFail2ban() async {
    final installed = await checkLinuxFail2banInstalled();
    if (!installed) return null;
    final result = await CommandRunner.run(
      'systemctl',
      ['is-active', '--quiet', 'fail2ban'],
    );
    return result.success;
  }

  static Future<bool> installLinuxFail2ban() async {
    final distro = await OsDetector.detectLinuxDistro();
    String installCmd;
    switch (distro) {
      case LinuxDistro.debian:
        installCmd = 'apt update -qq && apt install fail2ban -y -qq';
        break;
      case LinuxDistro.fedora:
        installCmd = 'dnf install fail2ban -y -q';
        break;
      case LinuxDistro.arch:
        installCmd = 'pacman -S --noconfirm fail2ban';
        break;
      case LinuxDistro.unknown:
        return false;
    }
    final result = await _runLinuxElevated('#!/bin/bash\n$installCmd\nsystemctl enable --now fail2ban\nexit \$?\n');
    return result.success;
  }

  static Future<bool> enableLinuxFail2ban() async {
    final result = await _runLinuxElevated(
      '#!/bin/bash\nsystemctl enable --now fail2ban\nexit \$?\n',
    );
    return result.success;
  }

  static Future<bool> disableLinuxFail2ban() async {
    final result = await _runLinuxElevated(
      '#!/bin/bash\nsystemctl disable --now fail2ban\nexit \$?\n',
    );
    return result.success;
  }

  // --- Mises à jour auto sécurité ---
  static Future<bool?> checkLinuxUpdates() async {
    final distro = await OsDetector.detectLinuxDistro();
    switch (distro) {
      case LinuxDistro.debian:
        final result = await CommandRunner.run(
          'systemctl',
          ['is-active', '--quiet', 'unattended-upgrades'],
        );
        return result.success;
      case LinuxDistro.fedora:
        final result = await CommandRunner.run(
          'systemctl',
          ['is-active', '--quiet', 'dnf-automatic-install.timer'],
        );
        return result.success;
      default:
        return null;
    }
  }

  static Future<bool> enableLinuxUpdates() async {
    final distro = await OsDetector.detectLinuxDistro();
    switch (distro) {
      case LinuxDistro.debian:
        final script = '#!/bin/bash\n'
            'apt install -y -qq unattended-upgrades\n'
            'echo \'APT::Periodic::Update-Package-Lists "1";\' > /etc/apt/apt.conf.d/20auto-upgrades\n'
            'echo \'APT::Periodic::Unattended-Upgrade "1";\' >> /etc/apt/apt.conf.d/20auto-upgrades\n'
            'systemctl enable --now unattended-upgrades\n'
            'exit 0\n';
        final result = await _runLinuxElevated(script);
        return result.success;
      case LinuxDistro.fedora:
        final script = '#!/bin/bash\n'
            'dnf install -y -q dnf-automatic\n'
            'systemctl enable --now dnf-automatic-install.timer\n'
            'exit 0\n';
        final result = await _runLinuxElevated(script);
        return result.success;
      default:
        return false;
    }
  }

  static Future<bool> disableLinuxUpdates() async {
    final distro = await OsDetector.detectLinuxDistro();
    switch (distro) {
      case LinuxDistro.debian:
        final result = await _runLinuxElevated(
          '#!/bin/bash\nsystemctl disable --now unattended-upgrades\nexit \$?\n',
        );
        return result.success;
      case LinuxDistro.fedora:
        final result = await _runLinuxElevated(
          '#!/bin/bash\nsystemctl disable --now dnf-automatic-install.timer\nexit \$?\n',
        );
        return result.success;
      default:
        return false;
    }
  }

  // --- Login root SSH (inversé : true = PermitRootLogin no = sécurisé) ---
  static Future<bool?> checkLinuxRootLogin() async {
    // Vérifier dans sshd_config (lisible sans root)
    final result = await CommandRunner.run(
      'grep', ['-E', r'^\s*PermitRootLogin', '/etc/ssh/sshd_config'],
    );
    if (!result.success) {
      // Pas de ligne PermitRootLogin → le défaut sur la plupart des distros
      // est "prohibit-password" (sécurisé)
      return true;
    }
    final line = result.stdout.trim().toLowerCase();
    return line.contains('no') || line.contains('prohibit-password');
  }

  static Future<bool> enableLinuxRootLoginProtection() async {
    final script = '#!/bin/bash\n'
        'if grep -q "^#*PermitRootLogin" /etc/ssh/sshd_config; then\n'
        '  sed -i \'s/^#*PermitRootLogin.*/PermitRootLogin no/\' /etc/ssh/sshd_config\n'
        'else\n'
        '  echo "PermitRootLogin no" >> /etc/ssh/sshd_config\n'
        'fi\n'
        'systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null\n'
        'exit 0\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  static Future<bool> disableLinuxRootLoginProtection() async {
    final script = '#!/bin/bash\n'
        'if grep -q "^#*PermitRootLogin" /etc/ssh/sshd_config; then\n'
        '  sed -i \'s/^#*PermitRootLogin.*/PermitRootLogin yes/\' /etc/ssh/sshd_config\n'
        'else\n'
        '  echo "PermitRootLogin yes" >> /etc/ssh/sshd_config\n'
        'fi\n'
        'systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null\n'
        'exit 0\n';
    final result = await _runLinuxElevated(script);
    return result.success;
  }

  // --- rkhunter ---
  static Future<bool> checkLinuxRkhunterInstalled() async {
    final result = await CommandRunner.run('which', ['rkhunter']);
    return result.success;
  }

  static Future<bool> installLinuxRkhunter() async {
    final distro = await OsDetector.detectLinuxDistro();
    String installCmd;
    switch (distro) {
      case LinuxDistro.debian:
        installCmd = 'apt update -qq && apt install rkhunter -y -qq';
        break;
      case LinuxDistro.fedora:
        installCmd = 'dnf install rkhunter -y -q';
        break;
      case LinuxDistro.arch:
        installCmd = 'pacman -S --noconfirm rkhunter';
        break;
      case LinuxDistro.unknown:
        return false;
    }
    final result = await _runLinuxElevated('#!/bin/bash\n$installCmd\nexit \$?\n');
    return result.success;
  }

  // ============================================
  // MACOS
  // ============================================

  // --- Pare-feu applicatif ---
  static Future<bool?> checkMacFirewall() async {
    final result = await CommandRunner.run(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--getglobalstate'],
    );
    if (!result.success) return null;
    return result.stdout.contains('enabled');
  }

  static Future<bool> enableMacFirewall() async {
    final result = await CommandRunner.runElevated(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--setglobalstate', 'on'],
    );
    return result.success;
  }

  static Future<bool> disableMacFirewall() async {
    final result = await CommandRunner.runElevated(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--setglobalstate', 'off'],
    );
    return result.success;
  }

  // --- Mode furtif ---
  static Future<bool?> checkMacStealth() async {
    final result = await CommandRunner.run(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--getstealthmode'],
    );
    if (!result.success) return null;
    return result.stdout.contains('enabled');
  }

  static Future<bool> enableMacStealth() async {
    final result = await CommandRunner.runElevated(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--setstealthmode', 'on'],
    );
    return result.success;
  }

  static Future<bool> disableMacStealth() async {
    final result = await CommandRunner.runElevated(
      '/usr/libexec/ApplicationFirewall/socketfilterfw',
      ['--setstealthmode', 'off'],
    );
    return result.success;
  }

  // --- Partage de fichiers SMB (inversé : true = désactivé = sécurisé) ---
  static Future<bool?> checkMacSmb() async {
    final result = await CommandRunner.run('launchctl', [
      'list',
    ]);
    if (!result.success) return null;
    // Si smbd n'est pas dans la liste, il est désactivé = sécurisé
    return !result.stdout.contains('com.apple.smbd');
  }

  static Future<bool> enableMacSmbProtection() async {
    final result = await CommandRunner.runElevated('launchctl', [
      'unload',
      '-w',
      '/System/Library/LaunchDaemons/com.apple.smbd.plist',
    ]);
    return result.success;
  }

  static Future<bool> disableMacSmbProtection() async {
    final result = await CommandRunner.runElevated('launchctl', [
      'load',
      '-w',
      '/System/Library/LaunchDaemons/com.apple.smbd.plist',
    ]);
    return result.success;
  }

  // --- Mises à jour auto ---
  static Future<bool?> checkMacUpdates() async {
    final result = await CommandRunner.run('defaults', [
      'read',
      '/Library/Preferences/com.apple.SoftwareUpdate',
      'AutomaticCheckEnabled',
    ]);
    if (!result.success) return null;
    return result.stdout.trim() == '1';
  }

  static Future<bool> enableMacUpdates() async {
    final result = await CommandRunner.runElevated('bash', [
      '-c',
      'defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true && '
          'defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true && '
          'defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true',
    ]);
    return result.success;
  }

  static Future<bool> disableMacUpdates() async {
    final result = await CommandRunner.runElevated('defaults', [
      'write',
      '/Library/Preferences/com.apple.SoftwareUpdate',
      'AutomaticCheckEnabled',
      '-bool',
      'false',
    ]);
    return result.success;
  }

  // --- Saisie clavier sécurisée ---
  static Future<bool?> checkMacSecureKeyboard() async {
    final result = await CommandRunner.run('defaults', [
      'read',
      'com.apple.terminal',
      'SecureKeyboardEntry',
    ]);
    if (!result.success) return null;
    return result.stdout.trim() == '1';
  }

  static Future<bool> enableMacSecureKeyboard() async {
    final result = await CommandRunner.run('defaults', [
      'write',
      'com.apple.terminal',
      'SecureKeyboardEntry',
      '-bool',
      'true',
    ]);
    return result.success;
  }

  static Future<bool> disableMacSecureKeyboard() async {
    final result = await CommandRunner.run('defaults', [
      'write',
      'com.apple.terminal',
      'SecureKeyboardEntry',
      '-bool',
      'false',
    ]);
    return result.success;
  }

  // --- Gatekeeper ---
  static Future<bool?> checkMacGatekeeper() async {
    final result = await CommandRunner.run('spctl', ['--status']);
    if (!result.success) return null;
    return result.stdout.contains('assessments enabled');
  }

  static Future<bool> enableMacGatekeeper() async {
    final result = await CommandRunner.runElevated('spctl', ['--master-enable']);
    return result.success;
  }

  static Future<bool> disableMacGatekeeper() async {
    final result = await CommandRunner.runElevated('spctl', ['--master-disable']);
    return result.success;
  }

  // --- Verrouillage écran immédiat ---
  static Future<bool?> checkMacScreenLock() async {
    final result = await CommandRunner.run('defaults', [
      'read',
      'com.apple.screensaver',
      'askForPasswordDelay',
    ]);
    if (!result.success) return null;
    return result.stdout.trim() == '0';
  }

  static Future<bool> enableMacScreenLock() async {
    await CommandRunner.run('defaults', [
      'write',
      'com.apple.screensaver',
      'askForPassword',
      '-int',
      '1',
    ]);
    final result = await CommandRunner.run('defaults', [
      'write',
      'com.apple.screensaver',
      'askForPasswordDelay',
      '-int',
      '0',
    ]);
    return result.success;
  }

  static Future<bool> disableMacScreenLock() async {
    final result = await CommandRunner.run('defaults', [
      'write',
      'com.apple.screensaver',
      'askForPasswordDelay',
      '-int',
      '5',
    ]);
    return result.success;
  }

  // ============================================
  // SCANS (rkhunter / Defender)
  // ============================================

  /// Lance un scan rkhunter complet (Linux).
  /// Retourne la liste des warnings. Vide = rien détecté.
  static Future<List<String>> runRkhunterScan() async {
    final tempDir = await Directory.systemTemp.createTemp('chill-scan-');
    final outputFile = File('${tempDir.path}/rkhunter-results.txt');
    final tempScript = File('${tempDir.path}/scan.sh');

    final script = '#!/bin/bash\n'
        'export LANG=C\n'
        'export LC_ALL=C\n'
        '# Mettre a jour la base de donnees\n'
        'rkhunter --update 2>/dev/null\n'
        '# Lancer le scan (warnings uniquement)\n'
        'rkhunter --check --skip-keypress --rwo > "${outputFile.path}" 2>&1\n'
        'exit 0\n';

    await tempScript.writeAsString(script);
    await Process.run('chmod', ['700', tempDir.path]);
    await Process.run('chmod', ['700', tempScript.path]);

    try {
      await CommandRunner.run(
        'pkexec',
        ['bash', tempScript.path],
        timeout: const Duration(minutes: 10),
      );

      if (outputFile.existsSync()) {
        final content = await outputFile.readAsString();
        return content
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
      }
      return [];
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        debugPrint('[Security] Scan cleanup error: $e');
      }
    }
  }

  /// Lance un scan rapide Windows Defender.
  /// Retourne la liste des menaces trouvées. Vide = rien détecté.
  static Future<List<String>> runDefenderScan() async {
    // Mettre à jour les signatures d'abord
    await CommandRunner.runPowerShell(
      'Update-MpSignature -ErrorAction SilentlyContinue',
      timeout: const Duration(minutes: 2),
    );

    // Lancer le scan rapide (synchrone, peut prendre plusieurs minutes)
    final scan = await CommandRunner.runPowerShell(
      'Start-MpScan -ScanType QuickScan',
      timeout: const Duration(minutes: 15),
    );

    if (!scan.success) {
      return ['Erreur: ${scan.stderr}'];
    }

    // Vérifier les menaces récentes (dernière heure)
    final threats = await CommandRunner.runPowerShell(
      r'Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddHours(-1) } | ForEach-Object { $_.Resources -join ", " }',
    );

    if (threats.success && threats.stdout.isNotEmpty) {
      return threats.stdout
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
    }
    return [];
  }

  // ============================================
  // CHECKUP
  // ============================================

  /// Lance le checkup système complet.
  /// Retourne une liste de résultats [{id, label, status, detail}]
  static Future<List<Map<String, String>>> runCheckup() async {
    final os = OsDetector.currentOS;
    switch (os) {
      case SupportedOS.windows:
        return _runWindowsCheckup();
      case SupportedOS.linux:
        return _runLinuxCheckup();
      case SupportedOS.macos:
        return _runMacCheckup();
    }
  }

  static Future<List<Map<String, String>>> _runWindowsCheckup() async {
    final results = <Map<String, String>>[];

    // 1. Firewall
    final fw = await checkWindowsFirewall();
    results.add({
      'id': 'firewall',
      'status': fw == true ? 'ok' : (fw == false ? 'error' : 'warning'),
      'detail': fw == true ? 'active' : 'inactive',
    });

    // 2. Mises à jour (dernière date)
    // Force le format ISO yyyy-MM-dd pour éviter les dates localisées (FR: "samedi 14 février...")
    final updates = await CommandRunner.runPowerShell(
      "(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn.ToString('yyyy-MM-dd')",
    );
    if (updates.success && updates.stdout.isNotEmpty) {
      try {
        final lastUpdate = DateTime.parse(updates.stdout.trim());
        final daysSince = DateTime.now().difference(lastUpdate).inDays;
        results.add({
          'id': 'updates',
          'status': daysSince <= 30 ? 'ok' : (daysSince <= 90 ? 'warning' : 'error'),
          'detail': 'days:$daysSince',
        });
      } catch (_) {
        results.add({'id': 'updates', 'status': 'warning', 'detail': 'unknown'});
      }
    } else {
      results.add({'id': 'updates', 'status': 'warning', 'detail': 'unknown'});
    }

    // 3. Windows Defender
    final defender = await CommandRunner.runPowerShell(
      'Get-MpComputerStatus | Select-Object -ExpandProperty AntivirusEnabled',
    );
    results.add({
      'id': 'antivirus',
      'status': defender.stdout.trim() == 'True' ? 'ok' : 'error',
      'detail': defender.stdout.trim() == 'True' ? 'active' : 'inactive',
    });

    // 4. SMBv1
    final smb = await checkWindowsSmb1();
    results.add({
      'id': 'smb1',
      'status': smb == true ? 'ok' : 'error',
      'detail': smb == true ? 'disabled' : 'enabled',
    });

    // 5. Comptes utilisateurs
    final accounts = await CommandRunner.runPowerShell(
      'Get-LocalUser | Where-Object Enabled -eq True | Measure-Object | Select-Object -ExpandProperty Count',
    );
    results.add({
      'id': 'accounts',
      'status': 'ok',
      'detail': 'count:${accounts.stdout.trim()}',
    });

    // 6. Espace disque
    final disk = await CommandRunner.runPowerShell(
      r"Get-PSDrive C | ForEach-Object { [math]::Round($_.Used / ($_.Used + $_.Free) * 100) }",
    );
    if (disk.success) {
      final pct = int.tryParse(disk.stdout.trim()) ?? 0;
      results.add({
        'id': 'disk',
        'status': pct < 80 ? 'ok' : (pct < 90 ? 'warning' : 'error'),
        'detail': 'pct:$pct',
      });
    }

    return results;
  }

  static Future<List<Map<String, String>>> _runLinuxCheckup() async {
    // Écrire un script qui collecte tout et sort du JSON
    final tempDir = await Directory.systemTemp.createTemp('chill-checkup-');
    final outputFile = File('${tempDir.path}/results.json');
    final script = '#!/bin/bash\n'
        'export LANG=C\n'
        'export LC_ALL=C\n'
        '\n'
        '# 1. Firewall\n'
        'UFW_STATUS=\$(ufw status 2>/dev/null | head -1)\n'
        'if echo "\$UFW_STATUS" | grep -q "Status: active"; then\n'
        '  FW="ok"; FW_CODE="active"\n'
        'elif command -v ufw >/dev/null 2>&1; then\n'
        '  FW="error"; FW_CODE="inactive"\n'
        'else\n'
        '  FW="warning"; FW_CODE="missing"\n'
        'fi\n'
        '\n'
        '# 2. Sysctl\n'
        'REDIRECTS=\$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)\n'
        'if [ "\$REDIRECTS" = "0" ]; then\n'
        '  SYSCTL="ok"; SYSCTL_CODE="secure"\n'
        'else\n'
        '  SYSCTL="error"; SYSCTL_CODE="insecure"\n'
        'fi\n'
        '\n'
        '# 3. Permissions\n'
        'SHADOW_PERM=\$(stat -c "%a" /etc/shadow 2>/dev/null)\n'
        'if [ "\$SHADOW_PERM" = "600" ] || [ "\$SHADOW_PERM" = "640" ]; then\n'
        '  PERMS="ok"; PERMS_CODE="correct"\n'
        'else\n'
        '  PERMS="error"; PERMS_CODE="wrong:\$SHADOW_PERM"\n'
        'fi\n'
        '\n'
        '# 4. Fail2Ban\n'
        'if command -v fail2ban-client >/dev/null 2>&1; then\n'
        '  if systemctl is-active --quiet fail2ban 2>/dev/null; then\n'
        '    BANNED=\$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk \'{print \$NF}\')\n'
        '    F2B="ok"; F2B_CODE="active:\${BANNED:-0}"\n'
        '  else\n'
        '    F2B="warning"; F2B_CODE="inactive"\n'
        '  fi\n'
        'else\n'
        '  F2B="warning"; F2B_CODE="missing"\n'
        'fi\n'
        '\n'
        '# 5. Root login\n'
        'ROOT_STATUS=\$(passwd -S root 2>/dev/null | awk \'{print \$2}\')\n'
        'if [ "\$ROOT_STATUS" = "L" ] || [ "\$ROOT_STATUS" = "LK" ]; then\n'
        '  ROOT="ok"; ROOT_CODE="locked"\n'
        'else\n'
        '  ROOT="warning"; ROOT_CODE="unlocked"\n'
        'fi\n'
        '\n'
        '# 6. SSH failed logins\n'
        'FAILED=\$(journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" 2>/dev/null | grep -c "Failed password" 2>/dev/null || true)\n'
        'FAILED=\${FAILED:-0}\n'
        'if [ "\$FAILED" -le 5 ] 2>/dev/null; then\n'
        '  SSH_FAIL="ok"\n'
        'elif [ "\$FAILED" -le 50 ] 2>/dev/null; then\n'
        '  SSH_FAIL="warning"\n'
        'else\n'
        '  SSH_FAIL="error"\n'
        'fi\n'
        'SSH_FAIL_CODE="count:\$FAILED"\n'
        '\n'
        '# 7. Espace disque\n'
        'DISK_PCT=\$(df / | awk \'NR==2 {gsub("%",""); print \$5}\')\n'
        'if [ "\$DISK_PCT" -lt 80 ] 2>/dev/null; then\n'
        '  DISK="ok"\n'
        'elif [ "\$DISK_PCT" -lt 90 ] 2>/dev/null; then\n'
        '  DISK="warning"\n'
        'else\n'
        '  DISK="error"\n'
        'fi\n'
        'DISK_CODE="pct:\$DISK_PCT"\n'
        '\n'
        '# 8. Comptes avec shell\n'
        'ACCOUNTS=\$(awk -F: \'\$7 !~ /(nologin|false)/ {print \$1}\' /etc/passwd | wc -l)\n'
        'if [ "\$ACCOUNTS" -le 3 ] 2>/dev/null; then\n'
        '  ACCOUNTS_STATUS="ok"\n'
        'else\n'
        '  ACCOUNTS_STATUS="warning"\n'
        'fi\n'
        'ACCOUNTS_CODE="count:\$ACCOUNTS"\n'
        '\n'
        '# 9. rkhunter\n'
        'if command -v rkhunter >/dev/null 2>&1; then\n'
        '  if [ -f /var/lib/rkhunter/db/rkhunter.dat ]; then\n'
        '    RKH="ok"; RKH_CODE="configured"\n'
        '  else\n'
        '    RKH="warning"; RKH_CODE="noDb"\n'
        '  fi\n'
        'else\n'
        '  RKH="warning"; RKH_CODE="missing"\n'
        'fi\n'
        '\n'
        'san() { printf \'%s\' "\$1" | tr -d \'\\012\\015\\042\'; }\n'
        '\n'
        'cat > "${outputFile.path}" <<JSONEOF\n'
        '[\n'
        '  {"id":"firewall","status":"\$(san "\$FW")","detail":"\$(san "\$FW_CODE")"},\n'
        '  {"id":"network","status":"\$(san "\$SYSCTL")","detail":"\$(san "\$SYSCTL_CODE")"},\n'
        '  {"id":"permissions","status":"\$(san "\$PERMS")","detail":"\$(san "\$PERMS_CODE")"},\n'
        '  {"id":"fail2ban","status":"\$(san "\$F2B")","detail":"\$(san "\$F2B_CODE")"},\n'
        '  {"id":"rootLogin","status":"\$(san "\$ROOT")","detail":"\$(san "\$ROOT_CODE")"},\n'
        '  {"id":"failedLogins","status":"\$(san "\$SSH_FAIL")","detail":"\$(san "\$SSH_FAIL_CODE")"},\n'
        '  {"id":"rkhunter","status":"\$(san "\$RKH")","detail":"\$(san "\$RKH_CODE")"},\n'
        '  {"id":"disk","status":"\$(san "\$DISK")","detail":"\$(san "\$DISK_CODE")"},\n'
        '  {"id":"accounts","status":"\$(san "\$ACCOUNTS_STATUS")","detail":"\$(san "\$ACCOUNTS_CODE")"}\n'
        ']\n'
        'JSONEOF\n'
        'exit 0\n';

    final tempScript = File('${tempDir.path}/checkup.sh');
    await tempScript.writeAsString(script);
    await Process.run('chmod', ['700', tempDir.path]);
    await Process.run('chmod', ['700', tempScript.path]);

    try {
      final cmdResult = await CommandRunner.runElevated('bash', [tempScript.path]);

      if (outputFile.existsSync()) {
        final jsonStr = await outputFile.readAsString();
        try {
          final list = jsonDecode(jsonStr) as List;
          return list
              .map((e) => {
                    'id': e['id']?.toString() ?? '',
                    'status': e['status']?.toString() ?? 'warning',
                    'detail': e['detail']?.toString() ?? '',
                  })
              .toList();
        } catch (e) {
          debugPrint('[Security] JSON parse error: $e');
        }
      }

      // Fallback si le JSON n'a pas été créé
      if (!cmdResult.success) {
        return [
          {'id': 'error', 'status': 'error', 'detail': 'Checkup échoué: ${cmdResult.stderr}'}
        ];
      }
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        debugPrint('[Security] Cleanup error: $e');
      }
    }

    return [];
  }

  static Future<List<Map<String, String>>> _runMacCheckup() async {
    final results = <Map<String, String>>[];

    // 1. Firewall
    final fw = await checkMacFirewall();
    results.add({
      'id': 'firewall',
      'status': fw == true ? 'ok' : 'error',
      'detail': fw == true ? 'active' : 'inactive',
    });

    // 2. Stealth
    final stealth = await checkMacStealth();
    results.add({
      'id': 'stealth',
      'status': stealth == true ? 'ok' : 'warning',
      'detail': stealth == true ? 'active' : 'inactive',
    });

    // 3. Gatekeeper
    final gk = await checkMacGatekeeper();
    results.add({
      'id': 'gatekeeper',
      'status': gk == true ? 'ok' : 'error',
      'detail': gk == true ? 'active' : 'inactive',
    });

    // 4. Mises à jour
    final updates = await checkMacUpdates();
    results.add({
      'id': 'updates',
      'status': updates == true ? 'ok' : 'warning',
      'detail': updates == true ? 'active' : 'inactive',
    });

    // 5. Secure keyboard
    final sk = await checkMacSecureKeyboard();
    results.add({
      'id': 'secureKeyboard',
      'status': sk == true ? 'ok' : 'warning',
      'detail': sk == true ? 'active' : 'inactive',
    });

    // 6. Screen lock
    final sl = await checkMacScreenLock();
    results.add({
      'id': 'screenLock',
      'status': sl == true ? 'ok' : 'warning',
      'detail': sl == true ? 'active' : 'inactive',
    });

    // 7. Espace disque
    final disk = await CommandRunner.run('df', ['-h', '/']);
    if (disk.success) {
      final lines = disk.stdout.split('\n');
      if (lines.length >= 2) {
        final pctMatch = RegExp(r'(\d+)%').firstMatch(lines[1]);
        if (pctMatch != null) {
          final pct = int.parse(pctMatch.group(1)!);
          results.add({
            'id': 'disk',
            'status': pct < 80 ? 'ok' : (pct < 90 ? 'warning' : 'error'),
            'detail': 'pct:$pct',
          });
        }
      }
    }

    return results;
  }
}

