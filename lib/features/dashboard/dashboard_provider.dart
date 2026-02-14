import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';
import '../tailscale/tailscale_provider.dart';

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
    // Écouter les changements Tailscale pour le badge dashboard
    ref.listen<TailscaleState>(tailscaleProvider, (_, next) {
      if (next.status == TailscaleConnectionStatus.loading) return;
      state = state.copyWith(
        tailscaleConnected: next.status == TailscaleConnectionStatus.connected,
      );
    });

    Future.microtask(() => checkAll());
    return const DashboardState();
  }

  Future<void> checkAll() async {
    final os = OsDetector.currentOS;
    final results = await Future.wait([
      _checkSsh(os),
      _checkWol(os),
    ]);
    state = DashboardState(
      sshConfigured: results[0],
      wolConfigured: results[1],
      tailscaleConnected: state.tailscaleConnected,
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
          // Utilise RegistryKeyword/RegistryValue pour être indépendant de la langue Windows
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
            "| Where-Object { \$_.RegistryKeyword -eq '*WakeOnMagicPacket' -and \$_.RegistryValue -contains '1' }; "
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

}
