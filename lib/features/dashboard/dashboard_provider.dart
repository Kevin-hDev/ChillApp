import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

class DashboardState {
  final bool? sshConfigured;
  final bool? wolConfigured;
  final bool? tailscaleConnected;

  const DashboardState({this.sshConfigured, this.wolConfigured, this.tailscaleConnected});

  DashboardState copyWith({bool? sshConfigured, bool? wolConfigured, bool? tailscaleConnected}) {
    return DashboardState(
      sshConfigured: sshConfigured ?? this.sshConfigured,
      wolConfigured: wolConfigured ?? this.wolConfigured,
      tailscaleConnected: tailscaleConnected ?? this.tailscaleConnected,
    );
  }
}

final dashboardProvider =
    NotifierProvider<DashboardNotifier, DashboardState>(DashboardNotifier.new);

class DashboardNotifier extends Notifier<DashboardState> {
  @override
  DashboardState build() {
    Future.microtask(() => checkAll());
    return const DashboardState();
  }

  Future<void> checkAll() async {
    final os = OsDetector.currentOS;
    // Lancer les vérifications en parallèle
    final results = await Future.wait([
      _checkSsh(os),
      _checkWol(os),
      _checkTailscale(os),
    ]);
    state = DashboardState(
      sshConfigured: results[0],
      wolConfigured: results[1],
      tailscaleConnected: results[2],
    );
  }

  /// Vérifie si SSH est actif
  Future<bool> _checkSsh(SupportedOS os) async {
    try {
      switch (os) {
        case SupportedOS.windows:
          final result = await CommandRunner.runPowerShell(
            "(Get-Service sshd -ErrorAction SilentlyContinue).Status",
          );
          return result.stdout.contains('Running');

        case SupportedOS.linux:
          var result = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'sshd']);
          if (result.success) return true;
          result = await CommandRunner.run('systemctl', ['is-active', '--quiet', 'ssh']);
          return result.success;

        case SupportedOS.macos:
          final result = await CommandRunner.run('systemsetup', ['-getremotelogin']);
          return result.stdout.contains('On');
      }
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si WoL est actif
  Future<bool> _checkWol(SupportedOS os) async {
    try {
      switch (os) {
        case SupportedOS.windows:
          final result = await CommandRunner.runPowerShell(
            "\$a = Get-NetAdapter | Where-Object { "
            "\$_.Status -eq 'Up' -and "
            "\$_.InterfaceDescription -notlike '*Wi-Fi*' -and "
            "\$_.InterfaceDescription -notlike '*Wireless*' -and "
            "\$_.InterfaceDescription -notlike '*Bluetooth*' -and "
            "\$_.InterfaceDescription -notlike '*Virtual*' "
            "} | Select-Object -First 1; "
            "if (\$a) { "
            "\$p = Get-NetAdapterAdvancedProperty -Name \$a.Name -ErrorAction SilentlyContinue "
            "| Where-Object { \$_.DisplayName -like '*Wake*Magic*' -and \$_.DisplayValue -eq 'Enabled' }; "
            "if (\$p) { Write-Output 'OK' } }",
          );
          return result.stdout.contains('OK');

        case SupportedOS.linux:
          // Vérifier si le service wol-enable est activé (créé par notre app)
          final result = await CommandRunner.run(
            'systemctl', ['is-enabled', '--quiet', 'wol-enable.service'],
          );
          return result.success;

        case SupportedOS.macos:
          return false; // WoL non disponible sur Mac
      }
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si Tailscale est connecté
  Future<bool> _checkTailscale(SupportedOS os) async {
    try {
      // Vérifier si tailscale est installé
      CommandResult whichResult;
      switch (os) {
        case SupportedOS.windows:
          whichResult = await CommandRunner.runPowerShell(
            'Get-Command tailscale -ErrorAction SilentlyContinue',
          );
          if (!whichResult.success || whichResult.stdout.isEmpty) return false;
        case SupportedOS.linux:
        case SupportedOS.macos:
          whichResult = await CommandRunner.run('which', ['tailscale']);
          if (!whichResult.success) return false;
      }
      // Vérifier si connecté
      final result = await CommandRunner.run('tailscale', ['status', '--json']);
      if (!result.success) return false;
      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      final backendState = json['BackendState'] as String? ?? '';
      return backendState == 'Running';
    } catch (_) {
      return false;
    }
  }
}
