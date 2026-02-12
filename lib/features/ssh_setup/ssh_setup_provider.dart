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
  final String? ipAddress;
  final String? username;
  final String? errorMessage;

  const SshSetupState({
    this.steps = const [],
    this.isRunning = false,
    this.isComplete = false,
    this.ipAddress,
    this.username,
    this.errorMessage,
  });

  SshSetupState copyWith({
    List<SetupStep>? steps,
    bool? isRunning,
    bool? isComplete,
    String? ipAddress,
    String? username,
    String? errorMessage,
  }) {
    return SshSetupState(
      steps: steps ?? this.steps,
      isRunning: isRunning ?? this.isRunning,
      isComplete: isComplete ?? this.isComplete,
      ipAddress: ipAddress ?? this.ipAddress,
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
    final ipResult = await CommandRunner.runPowerShell(
      "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.InterfaceAlias -notlike '*Loopback*' -and \$_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress",
    );
    final userResult = await CommandRunner.runPowerShell("\$env:USERNAME");
    state = state.copyWith(
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
    _updateStep('info', StepStatus.success);
  }

  // ============================================
  // LINUX
  // ============================================
  Future<void> _runLinux() async {
    final distro = await OsDetector.detectLinuxDistro();

    // 1. Installer OpenSSH
    _updateStep('install', StepStatus.running);
    CommandResult result;
    switch (distro) {
      case LinuxDistro.debian:
        result = await CommandRunner.runElevated('bash', ['-c', 'apt update -qq && apt install openssh-server -y -qq']);
        break;
      case LinuxDistro.fedora:
        result = await CommandRunner.runElevated('bash', ['-c', 'dnf install openssh-server -y -q']);
        break;
      case LinuxDistro.arch:
        result = await CommandRunner.runElevated('bash', ['-c', 'pacman -S --noconfirm openssh']);
        break;
      case LinuxDistro.unknown:
        _updateStep('install', StepStatus.error, errorDetail: 'Distribution non reconnue');
        throw Exception('Distribution Linux non reconnue');
    }
    if (!result.success) {
      _updateStep('install', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec installation OpenSSH');
    }
    _updateStep('install', StepStatus.success);

    // 2. Démarrer et activer SSH
    _updateStep('start', StepStatus.running);
    result = await CommandRunner.runElevated('systemctl', ['enable', '--now', 'sshd']);
    // Certaines distros utilisent 'ssh' au lieu de 'sshd'
    if (!result.success) {
      result = await CommandRunner.runElevated('systemctl', ['enable', '--now', 'ssh']);
    }
    if (!result.success) {
      _updateStep('start', StepStatus.error, errorDetail: result.stderr);
      throw Exception('Échec démarrage SSH');
    }
    _updateStep('start', StepStatus.success);

    // 3. Vérifier que SSH tourne
    _updateStep('verify', StepStatus.running);
    result = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'sshd']);
    if (!result.success) {
      result = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'ssh']);
    }
    if (!result.success) {
      _updateStep('verify', StepStatus.error, errorDetail: 'SSH ne semble pas actif');
      throw Exception('SSH non actif');
    }
    _updateStep('verify', StepStatus.success);

    // 4. Configurer le pare-feu
    _updateStep('firewall', StepStatus.running);
    // Vérifier si ufw est installé et actif
    final ufwCheck = await CommandRunner.run('bash', ['-c', 'command -v ufw']);
    if (ufwCheck.success) {
      final ufwStatus = await CommandRunner.run('bash', ['-c', 'ufw status 2>/dev/null | grep -q "Status: active"']);
      if (ufwStatus.success) {
        await CommandRunner.runElevated('ufw', ['allow', 'ssh']);
      }
    } else {
      // Vérifier firewalld
      final fwCheck = await CommandRunner.run('bash', ['-c', 'command -v firewall-cmd']);
      if (fwCheck.success) {
        final fwActive = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'firewalld']);
        if (fwActive.success) {
          await CommandRunner.runElevated('firewall-cmd', ['--permanent', '--add-service=ssh']);
          await CommandRunner.runElevated('firewall-cmd', ['--reload']);
        }
      }
    }
    _updateStep('firewall', StepStatus.success);

    // 5. Récupérer les infos
    _updateStep('info', StepStatus.running);
    final ipResult = await CommandRunner.run('hostname', ['-I']);
    final userResult = await CommandRunner.run('whoami', []);
    final ip = ipResult.stdout.split(' ').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    state = state.copyWith(
      ipAddress: ip.isNotEmpty ? ip : null,
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
    var ipResult = await CommandRunner.run('ipconfig', ['getifaddr', 'en0']);
    if (!ipResult.success || ipResult.stdout.isEmpty) {
      ipResult = await CommandRunner.run('ipconfig', ['getifaddr', 'en1']);
    }
    final userResult = await CommandRunner.run('whoami', []);
    state = state.copyWith(
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
    _updateStep('info', StepStatus.success);
  }
}
