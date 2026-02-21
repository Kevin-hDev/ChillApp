import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/network_info.dart';

class ConnectionInfoState {
  final String? ipEthernet;
  final String? ipWifi;
  final String? macAddress;
  final String? hostname;
  final String? username;
  final String? adapterName;
  final bool isLoading;
  final String? error;

  const ConnectionInfoState({
    this.ipEthernet,
    this.ipWifi,
    this.macAddress,
    this.hostname,
    this.username,
    this.adapterName,
    this.isLoading = false,
    this.error,
  });

  ConnectionInfoState copyWith({
    String? ipEthernet,
    String? ipWifi,
    String? macAddress,
    String? hostname,
    String? username,
    String? adapterName,
    bool? isLoading,
    String? error,
  }) {
    return ConnectionInfoState(
      ipEthernet: ipEthernet ?? this.ipEthernet,
      ipWifi: ipWifi ?? this.ipWifi,
      macAddress: macAddress ?? this.macAddress,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      adapterName: adapterName ?? this.adapterName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final connectionInfoProvider =
    NotifierProvider<ConnectionInfoNotifier, ConnectionInfoState>(
      ConnectionInfoNotifier.new,
    );

class ConnectionInfoNotifier extends Notifier<ConnectionInfoState> {
  DateTime? _lastFetch;
  static const _ttl = Duration(minutes: 5);

  @override
  ConnectionInfoState build() {
    // Auto-fetch dès que le provider est lu
    Future.microtask(() => fetchAll());
    return const ConnectionInfoState(isLoading: true);
  }

  /// Récupère toutes les infos de connexion (cache TTL 5 min)
  Future<void> fetchAll({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final ipEthernet = await NetworkInfo.getEthernetIp();
      final ipWifi = await NetworkInfo.getWifiIp();
      final hostname = await NetworkInfo.getHostname();
      final username = await NetworkInfo.getUsername();

      // MAC + adapter name (Linux seulement via NetworkInfo, Windows via PowerShell)
      String? macAddress;
      String? adapterName;

      if (Platform.isWindows) {
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
        if (adapterResult.stdout.contains('|||')) {
          final parts = adapterResult.stdout.split('|||');
          adapterName = parts[0].trim();
          macAddress = parts.length > 1 ? parts[1].trim() : null;
        }
      } else if (Platform.isLinux) {
        adapterName = await NetworkInfo.findEthernetAdapter();
        if (adapterName != null) {
          macAddress = await NetworkInfo.getMacAddress(adapterName);
        }
      }

      _lastFetch = DateTime.now();
      state = state.copyWith(
        ipEthernet: ipEthernet,
        ipWifi: ipWifi,
        macAddress: macAddress,
        hostname: hostname,
        username: username,
        adapterName: adapterName,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
