import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

class ConnectionInfoState {
  final String? ipEthernet;
  final String? ipWifi;
  final String? macAddress;
  final String? username;
  final String? adapterName;
  final bool isLoading;
  final String? error;

  const ConnectionInfoState({
    this.ipEthernet,
    this.ipWifi,
    this.macAddress,
    this.username,
    this.adapterName,
    this.isLoading = false,
    this.error,
  });

  ConnectionInfoState copyWith({
    String? ipEthernet,
    String? ipWifi,
    String? macAddress,
    String? username,
    String? adapterName,
    bool? isLoading,
    String? error,
  }) {
    return ConnectionInfoState(
      ipEthernet: ipEthernet ?? this.ipEthernet,
      ipWifi: ipWifi ?? this.ipWifi,
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
      ipEthernet: ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null,
      ipWifi: wifiIpResult.stdout.isNotEmpty ? wifiIpResult.stdout : null,
      macAddress: macAddress,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
      adapterName: adapterName,
    );
  }

  // ============================================
  // LINUX
  // ============================================
  Future<void> _fetchLinux() async {
    // Username
    final userResult = await CommandRunner.run('whoami', []);

    // Trouver l'interface Ethernet + IP + MAC
    final ethResult = await CommandRunner.run('bash', ['-c',
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
    String? ipEthernet;
    if (ethResult.success && ethResult.stdout.isNotEmpty) {
      adapterName = ethResult.stdout.trim();
      final macResult = await CommandRunner.run('cat', ['/sys/class/net/$adapterName/address']);
      macAddress = macResult.stdout.isNotEmpty ? macResult.stdout : null;
      final ethIpResult = await CommandRunner.run('bash', ['-c',
        "ip -4 addr show $adapterName 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      ipEthernet = ethIpResult.stdout.isNotEmpty ? ethIpResult.stdout : null;
    }

    // Trouver l'interface WiFi + IP
    String? ipWifi;
    final wifiResult = await CommandRunner.run('bash', ['-c',
      'for iface in \$(ls /sys/class/net/); do '
      'if [ -d "/sys/class/net/\$iface/wireless" ]; then '
      'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
      'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
      'fi; '
      'done; '
      'exit 1',
    ]);
    if (wifiResult.success && wifiResult.stdout.isNotEmpty) {
      final wifiIface = wifiResult.stdout.trim();
      final wifiIpResult = await CommandRunner.run('bash', ['-c',
        "ip -4 addr show $wifiIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      ipWifi = wifiIpResult.stdout.isNotEmpty ? wifiIpResult.stdout : null;
    }

    state = state.copyWith(
      ipEthernet: ipEthernet,
      ipWifi: ipWifi,
      macAddress: macAddress,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
      adapterName: adapterName,
    );
  }

  // ============================================
  // MAC
  // ============================================
  Future<void> _fetchMac() async {
    // WiFi = en0 sur Mac, Ethernet = en1 (ou inversé selon le modèle)
    final en0Result = await CommandRunner.run('ipconfig', ['getifaddr', 'en0']);
    final en1Result = await CommandRunner.run('ipconfig', ['getifaddr', 'en1']);

    // Détecter lequel est WiFi via networksetup
    final hwResult = await CommandRunner.run('networksetup', ['-listallhardwareports']);
    final hwOutput = hwResult.stdout;
    String? wifiIface;
    String? ethIface;
    final lines = hwOutput.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Wi-Fi')) {
        // La ligne suivante contient "Device: enX"
        if (i + 1 < lines.length) {
          final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
          if (match != null) wifiIface = match.group(1);
        }
      } else if (lines[i].contains('Ethernet') || lines[i].contains('Thunderbolt')) {
        if (i + 1 < lines.length) {
          final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
          if (match != null) ethIface = match.group(1);
        }
      }
    }

    String? ipWifi;
    String? ipEthernet;
    if (wifiIface != null) {
      final r = await CommandRunner.run('ipconfig', ['getifaddr', wifiIface]);
      ipWifi = r.stdout.isNotEmpty ? r.stdout : null;
    }
    if (ethIface != null) {
      final r = await CommandRunner.run('ipconfig', ['getifaddr', ethIface]);
      ipEthernet = r.stdout.isNotEmpty ? r.stdout : null;
    }
    // Fallback si on n'a pas trouvé les interfaces
    if (ipWifi == null && ipEthernet == null) {
      if (en0Result.success && en0Result.stdout.isNotEmpty) {
        ipWifi = en0Result.stdout;
      }
      if (en1Result.success && en1Result.stdout.isNotEmpty) {
        ipEthernet = en1Result.stdout;
      }
    }

    // Username
    final userResult = await CommandRunner.run('whoami', []);

    state = state.copyWith(
      ipEthernet: ipEthernet,
      ipWifi: ipWifi,
      username: userResult.stdout.isNotEmpty ? userResult.stdout : null,
    );
  }
}
