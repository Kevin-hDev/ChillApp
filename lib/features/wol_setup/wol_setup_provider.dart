import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';
import '../ssh_setup/ssh_setup_provider.dart';

class WolSetupState {
  final List<SetupStep> steps;
  final bool isRunning;
  final bool isComplete;
  final String? macAddress;
  final String? ipEthernet;
  final String? ipWifi;
  final String? adapterName;
  final String? errorMessage;

  const WolSetupState({
    this.steps = const [],
    this.isRunning = false,
    this.isComplete = false,
    this.macAddress,
    this.ipEthernet,
    this.ipWifi,
    this.adapterName,
    this.errorMessage,
  });

  WolSetupState copyWith({
    List<SetupStep>? steps,
    bool? isRunning,
    bool? isComplete,
    String? macAddress,
    String? ipEthernet,
    String? ipWifi,
    String? adapterName,
    String? errorMessage,
  }) {
    return WolSetupState(
      steps: steps ?? this.steps,
      isRunning: isRunning ?? this.isRunning,
      isComplete: isComplete ?? this.isComplete,
      macAddress: macAddress ?? this.macAddress,
      ipEthernet: ipEthernet ?? this.ipEthernet,
      ipWifi: ipWifi ?? this.ipWifi,
      adapterName: adapterName ?? this.adapterName,
      errorMessage: errorMessage,
    );
  }
}

final wolSetupProvider = NotifierProvider<WolSetupNotifier, WolSetupState>(WolSetupNotifier.new);

class WolSetupNotifier extends Notifier<WolSetupState> {
  @override
  WolSetupState build() {
    return WolSetupState(steps: _buildSteps());
  }

  /// Construit la liste des étapes selon l'OS
  List<SetupStep> _buildSteps() {
    final os = OsDetector.currentOS;
    switch (os) {
      case SupportedOS.windows:
        return const [
          SetupStep(id: 'findAdapter'),
          SetupStep(id: 'enableMagicPacket'),
          SetupStep(id: 'enableWake'),
          SetupStep(id: 'disableFastStartup'),
          SetupStep(id: 'showMac'),
        ];
      case SupportedOS.linux:
        return const [
          SetupStep(id: 'installEthtool'),
          SetupStep(id: 'findAdapter'),
          SetupStep(id: 'enableWol'),
          SetupStep(id: 'persist'),
          SetupStep(id: 'showMac'),
        ];
      case SupportedOS.macos:
        return const []; // WoL non disponible sur Mac
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
          throw Exception('WoL non disponible sur Mac');
      }
      state = state.copyWith(isRunning: false, isComplete: true);
    } catch (e) {
      state = state.copyWith(isRunning: false, errorMessage: e.toString());
    }
  }

  /// Réinitialiser pour réessayer
  void reset() {
    state = WolSetupState(steps: _buildSteps());
  }

  // ============================================
  // WINDOWS
  // ============================================
  Future<void> _runWindows() async {
    // 1. Trouver la carte réseau Ethernet
    _updateStep('findAdapter', StepStatus.running);
    var result = await CommandRunner.runPowerShell(
      "\$adapter = Get-NetAdapter | Where-Object { "
      "\$_.Status -eq 'Up' -and "
      "\$_.InterfaceDescription -notlike '*Wi-Fi*' -and "
      "\$_.InterfaceDescription -notlike '*Wireless*' -and "
      "\$_.InterfaceDescription -notlike '*Bluetooth*' -and "
      "\$_.InterfaceDescription -notlike '*Virtual*' "
      "} | Select-Object -First 1; "
      "if (-not \$adapter) { exit 1 } else { "
      "Write-Output (\$adapter.Name + '|||' + \$adapter.InterfaceDescription) }",
    );
    if (!result.success || result.stdout.isEmpty) {
      _updateStep('findAdapter', StepStatus.error,
          errorDetail: 'Aucune carte Ethernet trouvée. Vérifie que ton câble est branché.');
      throw Exception('Aucune carte Ethernet trouvée');
    }
    final parts = result.stdout.split('|||');
    final adapterName = parts[0].trim();
    final adapterDesc = parts.length > 1 ? parts[1].trim() : adapterName;
    state = state.copyWith(adapterName: adapterName);
    _updateStep('findAdapter', StepStatus.success);

    // 2. Activer Wake on Magic Packet
    _updateStep('enableMagicPacket', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "\$props = Get-NetAdapterAdvancedProperty -Name '$adapterName' "
      "-ErrorAction SilentlyContinue | Where-Object { "
      "\$_.DisplayName -like '*Wake*Magic*' -or "
      "\$_.DisplayName -like '*WOL*Magic*' }; "
      "if (\$props) { foreach (\$p in \$props) { "
      "Set-NetAdapterAdvancedProperty -Name '$adapterName' "
      "-DisplayName \$p.DisplayName -DisplayValue 'Enabled' "
      "-ErrorAction SilentlyContinue } }",
    );
    // Vérifier que le Magic Packet est bien activé
    final magicCheck = await CommandRunner.runPowerShell(
      "\$props = Get-NetAdapterAdvancedProperty -Name '$adapterName' "
      "-ErrorAction SilentlyContinue | Where-Object { "
      "(\$_.DisplayName -like '*Wake*Magic*' -or "
      "\$_.DisplayName -like '*WOL*Magic*') -and "
      "\$_.DisplayValue -eq 'Enabled' }; "
      "if (\$props) { Write-Output 'OK' } else { exit 1 }",
    );
    if (!magicCheck.success || !magicCheck.stdout.contains('OK')) {
      _updateStep('enableMagicPacket', StepStatus.error,
          errorDetail: 'L\'option Magic Packet n\'est pas disponible sur cette carte réseau. '
              'Vérifie dans le Gestionnaire de périphériques > Propriétés avancées de ta carte.');
      throw Exception('Magic Packet non disponible');
    }
    _updateStep('enableMagicPacket', StepStatus.success);

    // 3. Autoriser le réveil par le réseau
    _updateStep('enableWake', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "powercfg /deviceenablewake \"$adapterDesc\"",
    );
    // Vérifier que l'appareil est dans la liste de réveil
    final wakeCheck = await CommandRunner.runPowerShell(
      "\$devices = powercfg /devicequery wake_armed; "
      "if (\$devices -match [regex]::Escape('$adapterDesc')) { Write-Output 'OK' } else { exit 1 }",
    );
    if (!wakeCheck.success || !wakeCheck.stdout.contains('OK')) {
      _updateStep('enableWake', StepStatus.error,
          errorDetail: 'Impossible d\'autoriser le réveil réseau pour cette carte. '
              'Vérifie dans le Gestionnaire de périphériques > Gestion de l\'alimentation.');
      throw Exception('Réveil réseau non autorisé');
    }
    _updateStep('enableWake', StepStatus.success);

    // 4. Désactiver le démarrage rapide
    _updateStep('disableFastStartup', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power' "
      "/v HiberbootEnabled /t REG_DWORD /d 0 /f",
    );
    // Vérifier que la valeur a bien été modifiée
    final fastCheck = await CommandRunner.runPowerShell(
      "\$val = (Get-ItemProperty "
      "'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power' "
      "-Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled; "
      "if (\$val -eq 0) { Write-Output 'OK' } else { exit 1 }",
    );
    if (!fastCheck.success || !fastCheck.stdout.contains('OK')) {
      _updateStep('disableFastStartup', StepStatus.error,
          errorDetail: 'Le démarrage rapide n\'a pas pu être désactivé. '
              'L\'option n\'est peut-être pas disponible sur cette machine.');
      throw Exception('Échec désactivation du démarrage rapide');
    }
    _updateStep('disableFastStartup', StepStatus.success);

    // 5. Récupérer l'adresse MAC + IPs
    _updateStep('showMac', StepStatus.running);
    final macResult = await CommandRunner.runPowerShell(
      "(Get-NetAdapter -Name '$adapterName').MacAddress",
    );
    // IP Ethernet
    final ethIpResult = await CommandRunner.runPowerShell(
      "(Get-NetIPAddress -InterfaceAlias '$adapterName' "
      "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress",
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
    state = state.copyWith(
      macAddress: macResult.stdout.isNotEmpty ? macResult.stdout : null,
      ipEthernet: ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null,
      ipWifi: wifiIpResult.stdout.isNotEmpty ? wifiIpResult.stdout : null,
    );
    _updateStep('showMac', StepStatus.success);
  }

  // ============================================
  // LINUX (1 seul mot de passe pour toutes les commandes admin)
  // ============================================
  Future<void> _runLinux() async {
    final distro = await OsDetector.detectLinuxDistro();

    // 1. Vérifier si ethtool est installé (pas d'élévation)
    _updateStep('installEthtool', StepStatus.running);
    final checkResult = await CommandRunner.run('bash', ['-c', 'command -v ethtool']);
    final needsEthtoolInstall = !checkResult.success;
    if (!needsEthtoolInstall) {
      _updateStep('installEthtool', StepStatus.success);
    }

    // Préparer la commande d'installation si nécessaire
    String installCmd = '';
    if (needsEthtoolInstall) {
      switch (distro) {
        case LinuxDistro.debian:
          installCmd = 'apt update -qq && apt install ethtool -y -qq\n'
              'if [ \$? -ne 0 ]; then exit 10; fi\n';
          break;
        case LinuxDistro.fedora:
          installCmd = 'dnf install ethtool -y -q\n'
              'if [ \$? -ne 0 ]; then exit 10; fi\n';
          break;
        case LinuxDistro.arch:
          installCmd = 'pacman -S --noconfirm ethtool\n'
              'if [ \$? -ne 0 ]; then exit 10; fi\n';
          break;
        case LinuxDistro.unknown:
          _updateStep('installEthtool', StepStatus.error, errorDetail: 'Distribution non reconnue');
          throw Exception('Distribution Linux non reconnue');
      }
    }

    // 2. Trouver l'interface Ethernet (pas d'élévation)
    _updateStep('findAdapter', StepStatus.running);
    final findResult = await CommandRunner.run('bash', ['-c',
      'FALLBACK=""; '
      'for iface in \$(ls /sys/class/net/); do '
      'if [ "\$iface" = "lo" ]; then continue; fi; '
      'if [ -d "/sys/class/net/\$iface/wireless" ]; then continue; fi; '
      'if [ -e "/sys/class/net/\$iface/device" ]; then '
      'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
      'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
      'FALLBACK="\$iface"; '
      'fi; '
      'done; '
      'if [ -n "\$FALLBACK" ]; then echo "\$FALLBACK"; exit 0; fi; '
      'exit 1',
    ]);
    if (!findResult.success || findResult.stdout.isEmpty) {
      _updateStep('findAdapter', StepStatus.error,
          errorDetail: 'Aucune carte Ethernet trouvée. Vérifie que ton câble est branché.');
      throw Exception('Aucune carte Ethernet trouvée');
    }
    final ethIface = findResult.stdout.trim();
    state = state.copyWith(adapterName: ethIface);
    _updateStep('findAdapter', StepStatus.success);

    // 3. Écrire le fichier service temporaire (pas d'élévation)
    final serviceContent = '[Unit]\n'
        'Description=Enable Wake-on-LAN on $ethIface\n'
        'After=network-online.target\n'
        'Wants=network-online.target\n'
        '\n'
        '[Service]\n'
        'Type=oneshot\n'
        'ExecStart=/usr/sbin/ethtool -s $ethIface wol g\n'
        'RemainAfterExit=yes\n'
        '\n'
        '[Install]\n'
        'WantedBy=multi-user.target\n';
    final tempServiceFile = File('/tmp/wol-enable.service');
    await tempServiceFile.writeAsString(serviceContent);

    // === Toutes les commandes admin en 1 seul pkexec ===
    _updateStep('enableWol', StepStatus.running);

    final script =
        '#!/bin/bash\n'
        '$installCmd'
        '# Activer le WoL\n'
        'ethtool -s $ethIface wol g\n'
        'if [ \$? -ne 0 ]; then exit 20; fi\n'
        '\n'
        '# Vérifier que le WoL est actif\n'
        'WOL_LINE=\$(ethtool $ethIface 2>/dev/null | grep "Wake-on:" | tail -1)\n'
        'if ! echo "\$WOL_LINE" | grep -q "g"; then exit 30; fi\n'
        '\n'
        '# Rendre permanent (service systemd)\n'
        'cp /tmp/wol-enable.service /etc/systemd/system/wol-enable.service\n'
        'systemctl daemon-reload\n'
        'systemctl enable wol-enable.service\n'
        'if [ \$? -ne 0 ]; then exit 40; fi\n'
        '\n'
        'exit 0\n';

    final tempScript = File('/tmp/chill-wol-setup.sh');
    await tempScript.writeAsString(script);

    final result = await CommandRunner.runElevated('bash', [tempScript.path]);
    try { await tempScript.delete(); } catch (_) {}
    try { await tempServiceFile.delete(); } catch (_) {}

    // Analyser le résultat par code de sortie
    if (result.exitCode == 126 || result.exitCode == 127) {
      if (needsEthtoolInstall) {
        _updateStep('installEthtool', StepStatus.error, errorDetail: 'Autorisation refusée');
      }
      _updateStep('enableWol', StepStatus.error, errorDetail: 'Autorisation refusée');
      throw Exception('Autorisation refusée');
    }
    if (result.exitCode == 10) {
      _updateStep('installEthtool', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec installation ethtool');
    }
    if (needsEthtoolInstall) {
      _updateStep('installEthtool', StepStatus.success);
    }

    if (result.exitCode == 20) {
      _updateStep('enableWol', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec activation Wake-on-LAN');
    }
    if (result.exitCode == 30) {
      _updateStep('enableWol', StepStatus.error,
          errorDetail: 'Le WoL ne semble pas actif. Ta carte ne le supporte peut-être pas.');
      throw Exception('Wake-on-LAN non actif');
    }
    _updateStep('enableWol', StepStatus.success);

    if (result.exitCode == 40) {
      _updateStep('persist', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec création du service WoL');
    }
    _updateStep('persist', StepStatus.success);

    // === Récupération d'infos (pas d'élévation) ===
    _updateStep('showMac', StepStatus.running);
    final macResult = await CommandRunner.run('cat', ['/sys/class/net/$ethIface/address']);
    // IP Ethernet
    final ethIpResult = await CommandRunner.run('bash', ['-c',
      "ip -4 addr show $ethIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
    ]);
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
      macAddress: macResult.stdout.isNotEmpty ? macResult.stdout : null,
      ipEthernet: ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null,
      ipWifi: ipWifi,
    );
    _updateStep('showMac', StepStatus.success);
  }
}
