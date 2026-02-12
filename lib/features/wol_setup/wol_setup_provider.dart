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
  final String? ipAddress;
  final String? adapterName;
  final String? errorMessage;

  const WolSetupState({
    this.steps = const [],
    this.isRunning = false,
    this.isComplete = false,
    this.macAddress,
    this.ipAddress,
    this.adapterName,
    this.errorMessage,
  });

  WolSetupState copyWith({
    List<SetupStep>? steps,
    bool? isRunning,
    bool? isComplete,
    String? macAddress,
    String? ipAddress,
    String? adapterName,
    String? errorMessage,
  }) {
    return WolSetupState(
      steps: steps ?? this.steps,
      isRunning: isRunning ?? this.isRunning,
      isComplete: isComplete ?? this.isComplete,
      macAddress: macAddress ?? this.macAddress,
      ipAddress: ipAddress ?? this.ipAddress,
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
    _updateStep('enableMagicPacket', StepStatus.success);

    // 3. Autoriser le réveil par le réseau
    _updateStep('enableWake', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "powercfg /deviceenablewake \"$adapterDesc\"",
    );
    _updateStep('enableWake', StepStatus.success);

    // 4. Désactiver le démarrage rapide
    _updateStep('disableFastStartup', StepStatus.running);
    result = await CommandRunner.runPowerShell(
      "reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power' "
      "/v HiberbootEnabled /t REG_DWORD /d 0 /f",
    );
    if (!result.success) {
      _updateStep('disableFastStartup', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec désactivation du démarrage rapide');
    }
    _updateStep('disableFastStartup', StepStatus.success);

    // 5. Récupérer l'adresse MAC
    _updateStep('showMac', StepStatus.running);
    final macResult = await CommandRunner.runPowerShell(
      "(Get-NetAdapter -Name '$adapterName').MacAddress",
    );
    final ipResult = await CommandRunner.runPowerShell(
      "(Get-NetIPAddress -InterfaceAlias '$adapterName' "
      "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress",
    );
    state = state.copyWith(
      macAddress: macResult.stdout.isNotEmpty ? macResult.stdout : null,
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
    );
    _updateStep('showMac', StepStatus.success);
  }

  // ============================================
  // LINUX
  // ============================================
  Future<void> _runLinux() async {
    final distro = await OsDetector.detectLinuxDistro();

    // 1. Installer ethtool
    _updateStep('installEthtool', StepStatus.running);
    final checkResult = await CommandRunner.run('bash', ['-c', 'command -v ethtool']);
    if (!checkResult.success) {
      CommandResult result;
      switch (distro) {
        case LinuxDistro.debian:
          result = await CommandRunner.runElevated('bash', ['-c', 'apt update -qq && apt install ethtool -y -qq']);
          break;
        case LinuxDistro.fedora:
          result = await CommandRunner.runElevated('bash', ['-c', 'dnf install ethtool -y -q']);
          break;
        case LinuxDistro.arch:
          result = await CommandRunner.runElevated('bash', ['-c', 'pacman -S --noconfirm ethtool']);
          break;
        case LinuxDistro.unknown:
          _updateStep('installEthtool', StepStatus.error, errorDetail: 'Distribution non reconnue');
          throw Exception('Distribution Linux non reconnue');
      }
      if (!result.success) {
        _updateStep('installEthtool', StepStatus.error, errorDetail: result.stderr);
        throw Exception('Échec installation ethtool');
      }
    }
    _updateStep('installEthtool', StepStatus.success);

    // 2. Trouver l'interface Ethernet
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

    // 3. Activer le Wake-on-LAN
    _updateStep('enableWol', StepStatus.running);
    var result = await CommandRunner.runElevated('ethtool', ['-s', ethIface, 'wol', 'g']);
    if (!result.success) {
      _updateStep('enableWol', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec activation Wake-on-LAN');
    }
    // Vérifier que c'est bien actif
    final verifyResult = await CommandRunner.runElevated('ethtool', [ethIface]);
    final wolLine = verifyResult.stdout.split('\n')
        .where((l) => l.contains('Wake-on:'))
        .lastOrNull ?? '';
    if (!wolLine.contains('g')) {
      _updateStep('enableWol', StepStatus.error,
          errorDetail: 'Le WoL ne semble pas actif. Ta carte ne le supporte peut-être pas.');
      throw Exception('Wake-on-LAN non actif');
    }
    _updateStep('enableWol', StepStatus.success);

    // 4. Rendre le WoL permanent (service systemd)
    _updateStep('persist', StepStatus.running);
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

    // Écrire dans un fichier temporaire d'abord (pas besoin de sudo)
    final tempFile = File('/tmp/wol-enable.service');
    await tempFile.writeAsString(serviceContent);

    // Copier vers le dossier système + activer le service (besoin de sudo)
    result = await CommandRunner.runElevated('bash', ['-c',
      'cp /tmp/wol-enable.service /etc/systemd/system/wol-enable.service && '
      'systemctl daemon-reload && '
      'systemctl enable wol-enable.service',
    ]);
    // Nettoyer le fichier temporaire
    try { await tempFile.delete(); } catch (_) {}

    if (!result.success) {
      _updateStep('persist', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec création du service WoL');
    }
    _updateStep('persist', StepStatus.success);

    // 5. Récupérer l'adresse MAC
    _updateStep('showMac', StepStatus.running);
    final macResult = await CommandRunner.run('cat', ['/sys/class/net/$ethIface/address']);
    final ipResult = await CommandRunner.run('bash', ['-c',
      "ip -4 addr show $ethIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
    ]);
    state = state.copyWith(
      macAddress: macResult.stdout.isNotEmpty ? macResult.stdout : null,
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
    );
    _updateStep('showMac', StepStatus.success);
  }
}
