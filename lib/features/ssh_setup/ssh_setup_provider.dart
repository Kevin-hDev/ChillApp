import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

enum StepStatus { pending, running, success, error }

/// Représente une étape de configuration
class SetupStep {
  final String id;
  final StepStatus status;
  final String? errorDetail;

  const SetupStep({
    required this.id,
    this.status = StepStatus.pending,
    this.errorDetail,
  });

  SetupStep copyWith({StepStatus? status, String? errorDetail}) {
    return SetupStep(
      id: id,
      status: status ?? this.status,
      errorDetail: errorDetail ?? this.errorDetail,
    );
  }
}

class SshSetupState {
  final List<SetupStep> steps;
  final bool isRunning;
  final bool isComplete;
  final String? ipEthernet;
  final String? ipWifi;
  final String? username;
  final String? errorMessage;

  const SshSetupState({
    this.steps = const [],
    this.isRunning = false,
    this.isComplete = false,
    this.ipEthernet,
    this.ipWifi,
    this.username,
    this.errorMessage,
  });

  SshSetupState copyWith({
    List<SetupStep>? steps,
    bool? isRunning,
    bool? isComplete,
    String? ipEthernet,
    String? ipWifi,
    String? username,
    String? errorMessage,
  }) {
    return SshSetupState(
      steps: steps ?? this.steps,
      isRunning: isRunning ?? this.isRunning,
      isComplete: isComplete ?? this.isComplete,
      ipEthernet: ipEthernet ?? this.ipEthernet,
      ipWifi: ipWifi ?? this.ipWifi,
      username: username ?? this.username,
      errorMessage: errorMessage,
    );
  }
}

final sshSetupProvider = NotifierProvider<SshSetupNotifier, SshSetupState>(SshSetupNotifier.new);

class SshSetupNotifier extends Notifier<SshSetupState> {
  @override
  SshSetupState build() {
    return SshSetupState(steps: _buildSteps());
  }

  /// Construit la liste des étapes selon l'OS
  List<SetupStep> _buildSteps() {
    final os = OsDetector.currentOS;
    switch (os) {
      case SupportedOS.windows:
        return const [
          SetupStep(id: 'installClient'),
          SetupStep(id: 'installServer'),
          SetupStep(id: 'start'),
          SetupStep(id: 'autostart'),
          SetupStep(id: 'firewall'),
          SetupStep(id: 'verify'),
          SetupStep(id: 'info'),
        ];
      case SupportedOS.linux:
        return const [
          SetupStep(id: 'install'),
          SetupStep(id: 'start'),
          SetupStep(id: 'verify'),
          SetupStep(id: 'firewall'),
          SetupStep(id: 'info'),
        ];
      case SupportedOS.macos:
        return const [
          SetupStep(id: 'enableRemoteLogin'),
          SetupStep(id: 'verify'),
          SetupStep(id: 'info'),
        ];
    }
  }

  /// Met à jour le statut d'une étape
  void _updateStep(String id, StepStatus status, {String? errorDetail}) {
    final newSteps = state.steps.map((step) {
      if (step.id == id) return step.copyWith(status: status, errorDetail: errorDetail);
      return step;
    }).toList();
    state = state.copyWith(steps: newSteps);
  }

  /// Lance toute la configuration
  Future<void> runAll() async {
    state = state.copyWith(isRunning: true, isComplete: false, errorMessage: null);

    try {
      final os = OsDetector.currentOS;
      switch (os) {
        case SupportedOS.windows:
          await _runWindows();
          break;
        case SupportedOS.linux:
          await _runLinux();
          break;
        case SupportedOS.macos:
          await _runMac();
          break;
      }
      state = state.copyWith(isRunning: false, isComplete: true);
    } catch (e) {
      state = state.copyWith(isRunning: false, errorMessage: e.toString());
    }
  }

  /// Réinitialiser pour réessayer
  void reset() {
    state = SshSetupState(steps: _buildSteps());
  }

  // ============================================
  // WINDOWS
  // ============================================
  Future<void> _runWindows() async {
    // 1. Installer client OpenSSH (DOIT être avant le serveur)
    _updateStep('installClient', StepStatus.running);
    var result = await CommandRunner.runPowerShell(
      'Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0',
    );
    if (!result.success && !result.stderr.contains('already installed')) {
      _updateStep('installClient', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec installation client OpenSSH');
    }
    _updateStep('installClient', StepStatus.success);

    // 2. Installer serveur OpenSSH (après le client)
    _updateStep('installServer', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      'Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0',
    );
    if (!result.success && !result.stderr.contains('already installed')) {
      _updateStep('installServer', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec installation serveur OpenSSH');
    }
    _updateStep('installServer', StepStatus.success);

    // 3. Démarrer le service SSH
    _updateStep('start', StepStatus.running);
    result = await CommandRunner.runPowerShell('Start-Service sshd');
    if (!result.success && !result.stderr.contains('already running')) {
      _updateStep('start', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec démarrage SSH');
    }
    _updateStep('start', StepStatus.success);

    // 4. Activer SSH au démarrage
    _updateStep('autostart', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "Set-Service -Name sshd -StartupType 'Automatic'",
    );
    if (!result.success) {
      _updateStep('autostart', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec activation au démarrage');
    }
    _updateStep('autostart', StepStatus.success);

    // 5. Configurer le pare-feu
    _updateStep('firewall', StepStatus.running);
    // Vérifier si la règle existe déjà
    result = await CommandRunner.runPowerShell(
      "Get-NetFirewallRule -Name *ssh* -ErrorAction SilentlyContinue",
    );
    if (result.stdout.isEmpty) {
      // Créer la règle
      result = await CommandRunner.runPowerShell(
        "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' "
        "-Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22",
      );
      if (!result.success) {
        _updateStep('firewall', StepStatus.error, errorDetail: result.stderr);
        throw Exception('Échec configuration pare-feu');
      }
    }
    _updateStep('firewall', StepStatus.success);

    // 6. Vérifier que SSH fonctionne
    _updateStep('verify', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "(Get-Service sshd).Status",
    );
    if (!result.success || !result.stdout.contains('Running')) {
      _updateStep('verify', StepStatus.error, errorDetail: 'SSH ne semble pas actif');
      throw Exception('SSH non actif');
    }
    _updateStep('verify', StepStatus.success);

    // 7. Récupérer les infos
    _updateStep('info', StepStatus.running);
    // IP Ethernet
    final ethIpResult = await CommandRunner.runPowerShell(
      "\$a = Get-NetAdapter | Where-Object { "
      "\$_.Status -eq 'Up' -and "
      "\$_.InterfaceDescription -notlike '*Wi-Fi*' -and "
      "\$_.InterfaceDescription -notlike '*Wireless*' -and "
      "\$_.InterfaceDescription -notlike '*Bluetooth*' -and "
      "\$_.InterfaceDescription -notlike '*Virtual*' "
      "} | Select-Object -First 1; "
      "if (\$a) { (Get-NetIPAddress -InterfaceIndex \$a.ifIndex "
      "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress }",
    );
    // IP WiFi
    final wifiIpResult = await CommandRunner.runPowerShell(
      "\$a = Get-NetAdapter | Where-Object { "
      "\$_.Status -eq 'Up' -and "
      "(\$_.InterfaceDescription -like '*Wi-Fi*' -or "
      "\$_.InterfaceDescription -like '*Wireless*') "
      "} | Select-Object -First 1; "
      "if (\$a) { (Get-NetIPAddress -InterfaceIndex \$a.ifIndex "
      "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress }",
    );
    final userResult = await CommandRunner.runPowerShell("\$env:USERNAME");
    state = state.copyWith(
      ipEthernet: ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null,
      ipWifi: wifiIpResult.stdout.isNotEmpty ? wifiIpResult.stdout : null,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
    _updateStep('info', StepStatus.success);
  }

  // ============================================
  // LINUX (1 seul mot de passe pour toutes les commandes admin)
  // ============================================
  Future<void> _runLinux() async {
    final distro = await OsDetector.detectLinuxDistro();

    // Déterminer la commande d'installation selon la distro
    String installCmd;
    switch (distro) {
      case LinuxDistro.debian:
        installCmd = 'apt update -qq && apt install openssh-server -y -qq';
        break;
      case LinuxDistro.fedora:
        installCmd = 'dnf install openssh-server -y -q';
        break;
      case LinuxDistro.arch:
        installCmd = 'pacman -S --noconfirm openssh';
        break;
      case LinuxDistro.unknown:
        _updateStep('install', StepStatus.error, errorDetail: 'Distribution non reconnue');
        throw Exception('Distribution Linux non reconnue');
    }

    // === Phase 1 : toutes les commandes admin en 1 seul pkexec ===
    _updateStep('install', StepStatus.running);

    final script =
        '#!/bin/bash\n'
        '# 1. Installer OpenSSH\n'
        '$installCmd\n'
        'if [ \$? -ne 0 ]; then exit 10; fi\n'
        '\n'
        '# 2. Démarrer et activer SSH\n'
        'systemctl enable --now sshd 2>/dev/null || systemctl enable --now ssh\n'
        'if [ \$? -ne 0 ]; then exit 20; fi\n'
        '\n'
        '# 3. Configurer le pare-feu (non-critique)\n'
        'if command -v ufw >/dev/null 2>&1; then\n'
        '  ufw status 2>/dev/null | grep -q "Status: active" && ufw allow ssh 2>/dev/null\n'
        'elif command -v firewall-cmd >/dev/null 2>&1; then\n'
        '  systemctl is-active --quiet firewalld 2>/dev/null && '
        'firewall-cmd --permanent --add-service=ssh 2>/dev/null && '
        'firewall-cmd --reload 2>/dev/null\n'
        'fi\n'
        '\n'
        'exit 0\n';

    final tempScript = File('/tmp/chill-ssh-setup.sh');
    await tempScript.writeAsString(script);

    final result = await CommandRunner.runElevated('bash', [tempScript.path]);
    try { await tempScript.delete(); } catch (_) {}

    // Analyser le résultat par code de sortie
    if (result.exitCode == 126 || result.exitCode == 127) {
      _updateStep('install', StepStatus.error, errorDetail: 'Autorisation refusée');
      throw Exception('Autorisation refusée');
    }
    if (result.exitCode == 10) {
      _updateStep('install', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec installation OpenSSH');
    }
    _updateStep('install', StepStatus.success);

    if (result.exitCode == 20) {
      _updateStep('start', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec démarrage SSH');
    }
    _updateStep('start', StepStatus.success);
    _updateStep('firewall', StepStatus.success);

    // === Phase 2 : commandes sans élévation ===

    // 4. Vérifier que SSH tourne
    _updateStep('verify', StepStatus.running);
    var verifyResult = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'sshd']);
    if (!verifyResult.success) {
      verifyResult = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'ssh']);
    }
    if (!verifyResult.success) {
      _updateStep('verify', StepStatus.error, errorDetail: 'SSH ne semble pas actif');
      throw Exception('SSH non actif');
    }
    _updateStep('verify', StepStatus.success);

    // 5. Récupérer les infos
    _updateStep('info', StepStatus.running);
    final userResult = await CommandRunner.run('whoami', []);

    // IP Ethernet
    String? ipEthernet;
    final ethFind = await CommandRunner.run('bash', ['-c',
      'for iface in \$(ls /sys/class/net/); do '
      'if [ "\$iface" = "lo" ]; then continue; fi; '
      'if [ -d "/sys/class/net/\$iface/wireless" ]; then continue; fi; '
      'if [ -e "/sys/class/net/\$iface/device" ]; then '
      'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
      'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
      'fi; done; exit 1',
    ]);
    if (ethFind.success && ethFind.stdout.isNotEmpty) {
      final ethIface = ethFind.stdout.trim();
      final ethIpResult = await CommandRunner.run('bash', ['-c',
        "ip -4 addr show $ethIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      ipEthernet = ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null;
    }

    // IP WiFi
    String? ipWifi;
    final wifiFind = await CommandRunner.run('bash', ['-c',
      'for iface in \$(ls /sys/class/net/); do '
      'if [ -d "/sys/class/net/\$iface/wireless" ]; then '
      'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
      'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
      'fi; done; exit 1',
    ]);
    if (wifiFind.success && wifiFind.stdout.isNotEmpty) {
      final wifiIface = wifiFind.stdout.trim();
      final wifiIpResult = await CommandRunner.run('bash', ['-c',
        "ip -4 addr show $wifiIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      ipWifi = wifiIpResult.stdout.isNotEmpty ? wifiIpResult.stdout : null;
    }

    state = state.copyWith(
      ipEthernet: ipEthernet,
      ipWifi: ipWifi,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
    _updateStep('info', StepStatus.success);
  }

  // ============================================
  // MAC
  // ============================================
  Future<void> _runMac() async {
    // 1. Activer l'accès à distance
    _updateStep('enableRemoteLogin', StepStatus.running);
    final result = await CommandRunner.runElevated('systemsetup', ['-setremotelogin', 'on']);
    if (!result.success) {
      _updateStep('enableRemoteLogin', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec activation accès à distance');
    }
    _updateStep('enableRemoteLogin', StepStatus.success);

    // 2. Vérifier
    _updateStep('verify', StepStatus.running);
    final verifyResult = await CommandRunner.runElevated('systemsetup', ['-getremotelogin']);
    if (!verifyResult.stdout.contains('On')) {
      _updateStep('verify', StepStatus.error, errorDetail: 'SSH ne semble pas actif');
      throw Exception('SSH non actif');
    }
    _updateStep('verify', StepStatus.success);

    // 3. Récupérer les infos
    _updateStep('info', StepStatus.running);
    final userResult = await CommandRunner.run('whoami', []);

    // Détecter les interfaces WiFi et Ethernet
    String? ipWifi;
    String? ipEthernet;
    final hwResult = await CommandRunner.run('networksetup', ['-listallhardwareports']);
    final lines = hwResult.stdout.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Wi-Fi')) {
        if (i + 1 < lines.length) {
          final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
          if (match != null) {
            final r = await CommandRunner.run('ipconfig', ['getifaddr', match.group(1)!]);
            ipWifi = r.stdout.isNotEmpty ? r.stdout : null;
          }
        }
      } else if (lines[i].contains('Ethernet') || lines[i].contains('Thunderbolt')) {
        if (i + 1 < lines.length) {
          final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
          if (match != null) {
            final r = await CommandRunner.run('ipconfig', ['getifaddr', match.group(1)!]);
            ipEthernet = r.stdout.isNotEmpty ? r.stdout : null;
          }
        }
      }
    }
    // Fallback
    if (ipWifi == null && ipEthernet == null) {
      final en0 = await CommandRunner.run('ipconfig', ['getifaddr', 'en0']);
      if (en0.success && en0.stdout.isNotEmpty) ipWifi = en0.stdout;
      final en1 = await CommandRunner.run('ipconfig', ['getifaddr', 'en1']);
      if (en1.success && en1.stdout.isNotEmpty) ipEthernet = en1.stdout;
    }

    state = state.copyWith(
      ipEthernet: ipEthernet,
      ipWifi: ipWifi,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
    _updateStep('info', StepStatus.success);
  }
}
