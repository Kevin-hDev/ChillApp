import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

class ConnectionInfoState {
  final String? ipAddress;
  final String? macAddress;
  final String? username;
  final String? adapterName;
  final bool isLoading;
  final String? error;

  const ConnectionInfoState({
    this.ipAddress,
    this.macAddress,
    this.username,
    this.adapterName,
    this.isLoading = false,
    this.error,
  });

  ConnectionInfoState copyWith({
    String? ipAddress,
    String? macAddress,
    String? username,
    String? adapterName,
    bool? isLoading,
    String? error,
  }) {
    return ConnectionInfoState(
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      username: username ?? this.username,
      adapterName: adapterName ?? this.adapterName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final connectionInfoProvider =
    NotifierProvider<ConnectionInfoNotifier, ConnectionInfoState>(ConnectionInfoNotifier.new);

class ConnectionInfoNotifier extends Notifier<ConnectionInfoState> {
  @override
  ConnectionInfoState build() {
    // Auto-fetch dès que le provider est lu
    Future.microtask(() => fetchAll());
    return const ConnectionInfoState(isLoading: true);
  }

  /// Récupère toutes les infos de connexion
  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final os = OsDetector.currentOS;
      switch (os) {
        case SupportedOS.windows:
          await _fetchWindows();
          break;
        case SupportedOS.linux:
          await _fetchLinux();
          break;
        case SupportedOS.macos:
          await _fetchMac();
          break;
      }
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ============================================
  // WINDOWS
  // ============================================
  Future<void> _fetchWindows() async {
    // IP
    final ipResult = await CommandRunner.runPowerShell(
      "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { "
      "\$_.InterfaceAlias -notlike '*Loopback*' -and "
      "\$_.IPAddress -ne '127.0.0.1' } | "
      "Select-Object -First 1).IPAddress",
    );

    // Carte réseau Ethernet + MAC
    final adapterResult = await CommandRunner.runPowerShell(
      "\$a = Get-NetAdapter | Where-Object { "
      "\$_.Status -eq 'Up' -and "
      "\$_.InterfaceDescription -notlike '*Wi-Fi*' -and "
      "\$_.InterfaceDescription -notlike '*Wireless*' -and "
      "\$_.InterfaceDescription -notlike '*Bluetooth*' -and "
      "\$_.InterfaceDescription -notlike '*Virtual*' "
      "} | Select-Object -First 1; "
      "if (\$a) { Write-Output (\$a.Name + '|||' + \$a.MacAddress) }",
    );

    // Username
    final userResult = await CommandRunner.runPowerShell("\$env:USERNAME");

    String? adapterName;
    String? macAddress;
    if (adapterResult.stdout.contains('|||')) {
      final parts = adapterResult.stdout.split('|||');
      adapterName = parts[0].trim();
      macAddress = parts.length > 1 ? parts[1].trim() : null;
    }

    state = state.copyWith(
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
      macAddress: macAddress,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
      adapterName: adapterName,
    );
  }

  // ============================================
  // LINUX
  // ============================================
  Future<void> _fetchLinux() async {
    // IP
    final ipResult = await CommandRunner.run('hostname', ['-I']);
    final ip = ipResult.stdout.split(' ').firstWhere((s) => s.isNotEmpty, orElse: () => '');

    // Username
    final userResult = await CommandRunner.run('whoami', []);

    // Trouver l'interface Ethernet + MAC
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

    String? macAddress;
    String? adapterName;
    if (findResult.success && findResult.stdout.isNotEmpty) {
      adapterName = findResult.stdout.trim();
      final macResult = await CommandRunner.run('cat', ['/sys/class/net/$adapterName/address']);
      macAddress = macResult.stdout.isNotEmpty ? macResult.stdout : null;
    }

    state = state.copyWith(
      ipAddress: ip.isNotEmpty ? ip : null,
      macAddress: macAddress,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
      adapterName: adapterName,
    );
  }

  // ============================================
  // MAC
  // ============================================
  Future<void> _fetchMac() async {
    // IP
    var ipResult = await CommandRunner.run('ipconfig', ['getifaddr', 'en0']);
    if (!ipResult.success || ipResult.stdout.isEmpty) {
      ipResult = await CommandRunner.run('ipconfig', ['getifaddr', 'en1']);
    }

    // Username
    final userResult = await CommandRunner.run('whoami', []);

    state = state.copyWith(
      ipAddress: ipResult.stdout.isNotEmpty ? ipResult.stdout : null,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
      // MAC non disponible sur Mac en V1
    );
  }
}
