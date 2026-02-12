import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

enum TailscaleConnectionStatus {
  notInstalled,
  daemonStopped,
  loggedOut,
  connected,
  loading,
}

class TailscalePeer {
  final String hostname;
  final String ipv4;
  final String os;
  final bool isOnline;

  const TailscalePeer({
    required this.hostname,
    required this.ipv4,
    required this.os,
    required this.isOnline,
  });
}

class TailscaleState {
  final TailscaleConnectionStatus status;
  final String? selfHostname;
  final String? selfIp;
  final List<TailscalePeer> peers;
  final String? errorMessage;
  final bool isLoggingIn;

  const TailscaleState({
    this.status = TailscaleConnectionStatus.loading,
    this.selfHostname,
    this.selfIp,
    this.peers = const [],
    this.errorMessage,
    this.isLoggingIn = false,
  });

  TailscaleState copyWith({
    TailscaleConnectionStatus? status,
    String? selfHostname,
    String? selfIp,
    List<TailscalePeer>? peers,
    String? errorMessage,
    bool? isLoggingIn,
  }) {
    return TailscaleState(
      status: status ?? this.status,
      selfHostname: selfHostname ?? this.selfHostname,
      selfIp: selfIp ?? this.selfIp,
      peers: peers ?? this.peers,
      errorMessage: errorMessage,
      isLoggingIn: isLoggingIn ?? this.isLoggingIn,
    );
  }
}

final tailscaleProvider =
    NotifierProvider<TailscaleNotifier, TailscaleState>(TailscaleNotifier.new);

class TailscaleNotifier extends Notifier<TailscaleState> {
  Timer? _pollTimer;

  @override
  TailscaleState build() {
    Future.microtask(() => checkStatus());
    ref.onDispose(() => _pollTimer?.cancel());
    return const TailscaleState();
  }

  Future<bool> _isInstalled() async {
    final os = OsDetector.currentOS;
    switch (os) {
      case SupportedOS.windows:
        final result = await CommandRunner.runPowerShell(
          'Get-Command tailscale -ErrorAction SilentlyContinue',
        );
        return result.success && result.stdout.isNotEmpty;
      case SupportedOS.linux:
      case SupportedOS.macos:
        final result = await CommandRunner.run('which', ['tailscale']);
        return result.success;
    }
  }

  Future<void> checkStatus() async {
    state = state.copyWith(status: TailscaleConnectionStatus.loading, errorMessage: null);

    try {
      final installed = await _isInstalled();
      if (!installed) {
        state = state.copyWith(status: TailscaleConnectionStatus.notInstalled);
        _stopPolling();
        return;
      }

      final result = await CommandRunner.run('tailscale', ['status', '--json']);

      if (!result.success) {
        if (result.stderr.contains('is not running') ||
            result.stderr.contains('connection refused') ||
            result.stderr.contains('dial')) {
          state = state.copyWith(status: TailscaleConnectionStatus.daemonStopped);
          _stopPolling();
          return;
        }
        state = state.copyWith(
          status: TailscaleConnectionStatus.loggedOut,
          errorMessage: result.stderr,
        );
        _stopPolling();
        return;
      }

      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      final backendState = json['BackendState'] as String? ?? '';

      if (backendState == 'NeedsLogin' || backendState == 'NoState') {
        state = state.copyWith(status: TailscaleConnectionStatus.loggedOut);
        _stopPolling();
        return;
      }

      // Parse Self
      final self = json['Self'] as Map<String, dynamic>?;
      String? selfHostname;
      String? selfIp;
      if (self != null) {
        selfHostname = self['HostName'] as String?;
        final ips = self['TailscaleIPs'] as List<dynamic>?;
        if (ips != null && ips.isNotEmpty) {
          selfIp = ips.firstWhere(
            (ip) => ip.toString().contains('.'),
            orElse: () => ips.first,
          ).toString();
        }
      }

      // Parse Peers
      final peerMap = json['Peer'] as Map<String, dynamic>? ?? {};
      final peers = <TailscalePeer>[];
      for (final entry in peerMap.values) {
        final peer = entry as Map<String, dynamic>;
        final peerIps = peer['TailscaleIPs'] as List<dynamic>?;
        String peerIp = '';
        if (peerIps != null && peerIps.isNotEmpty) {
          peerIp = peerIps.firstWhere(
            (ip) => ip.toString().contains('.'),
            orElse: () => peerIps.first,
          ).toString();
        }
        peers.add(TailscalePeer(
          hostname: (peer['HostName'] as String?) ?? 'Unknown',
          ipv4: peerIp,
          os: (peer['OS'] as String?) ?? '',
          isOnline: peer['Online'] == true,
        ));
      }

      // Sort: online first, then alphabetical
      peers.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
      });

      state = state.copyWith(
        status: TailscaleConnectionStatus.connected,
        selfHostname: selfHostname,
        selfIp: selfIp,
        peers: peers,
      );
      _startPolling();
    } catch (e) {
      state = state.copyWith(
        status: TailscaleConnectionStatus.notInstalled,
        errorMessage: e.toString(),
      );
      _stopPolling();
    }
  }

  Future<void> login() async {
    state = state.copyWith(isLoggingIn: true, errorMessage: null);
    try {
      await CommandRunner.run('tailscale', ['up']);
      await checkStatus();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    } finally {
      state = state.copyWith(isLoggingIn: false);
    }
  }

  Future<void> logout() async {
    state = state.copyWith(errorMessage: null);
    try {
      await CommandRunner.run('tailscale', ['logout']);
      _stopPolling();
      state = state.copyWith(
        status: TailscaleConnectionStatus.loggedOut,
        selfHostname: null,
        selfIp: null,
        peers: [],
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> startDaemon() async {
    state = state.copyWith(errorMessage: null);
    try {
      final os = OsDetector.currentOS;
      if (os == SupportedOS.linux) {
        await CommandRunner.runElevated('systemctl', ['start', 'tailscaled']);
      }
      await Future.delayed(const Duration(seconds: 2));
      await checkStatus();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      checkStatus();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
