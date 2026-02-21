import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TailscaleConnectionStatus { loading, loggedOut, connected, error }

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

final tailscaleProvider = NotifierProvider<TailscaleNotifier, TailscaleState>(
  TailscaleNotifier.new,
);

class TailscaleNotifier extends Notifier<TailscaleState> {
  Process? _daemon;
  Timer? _pollTimer;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _isRetrying = false;

  @override
  TailscaleState build() {
    Future.microtask(() => _startDaemon());
    ref.onDispose(() => _shutdownDaemon());
    return const TailscaleState();
  }

  /// Vérifie qu'un binaire trouvé est exécutable (non-Windows uniquement)
  void _checkExecutable(String path) {
    if (Platform.isWindows) return;
    final stat = FileStat.statSync(path);
    final isExecutable = (stat.mode & 0x49) != 0; // owner|group|other execute
    if (!isExecutable) {
      debugPrint('[Tailscale] WARNING: Daemon found but not executable: $path');
    }
  }

  /// Trouve le binaire chill-tailscale à côté de l'exécutable Flutter
  String _getDaemonPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'chill-tailscale.exe' : 'chill-tailscale';
    final sep = Platform.pathSeparator;

    // Production : à côté de l'exécutable Flutter
    for (final sub in ['', '${sep}lib', '${sep}data']) {
      final path = '$exeDir$sub$sep$name';
      if (File(path).existsSync()) {
        _checkExecutable(path);
        return path;
      }
    }

    // Debug : remonter depuis build/<os>/x64/debug/bundle/ vers la racine du projet
    final buildPattern = Platform.isWindows
        ? RegExp(r'\\build\\.*$')
        : RegExp(r'/build/.*$');
    final projectDir = exeDir.replaceFirst(buildPattern, '');
    final debugPath = '$projectDir${sep}tailscale-daemon$sep$name';
    if (File(debugPath).existsSync()) {
      _checkExecutable(debugPath);
      return debugPath;
    }

    // macOS debug : le binaire peut avoir un suffixe -macos
    if (Platform.isMacOS) {
      final macDebugPath =
          '$projectDir${sep}tailscale-daemon${sep}chill-tailscale-macos';
      if (File(macDebugPath).existsSync()) {
        _checkExecutable(macDebugPath);
        return macDebugPath;
      }
    }

    // fallback PATH
    debugPrint(
      '[Tailscale] WARNING: Using PATH fallback for daemon. Binary not found at expected locations.',
    );
    return name;
  }

  /// Démarre le daemon Go chill-tailscale
  Future<void> _startDaemon() async {
    state = state.copyWith(
      status: TailscaleConnectionStatus.loading,
      errorMessage: null,
    );
    try {
      final daemonPath = _getDaemonPath();
      debugPrint('[Tailscale] Daemon path: $daemonPath');
      debugPrint('[Tailscale] File exists: ${File(daemonPath).existsSync()}');
      _daemon = await Process.start(daemonPath, []);

      // Écouter stdout ligne par ligne pour les événements JSON
      _stdoutSub = _daemon!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleEvent,
            onError: (_) => _onDaemonCrash(),
            onDone: _onDaemonCrash,
          );

      // Afficher stderr en debug (logs Go)
      _stderrSub = _daemon!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Tailscale daemon] $line'));

      // Envoyer la commande start
      _sendCommand({'cmd': 'start'});
    } catch (e) {
      debugPrint('[Tailscale] Erreur démarrage daemon: $e');
      state = state.copyWith(
        status: TailscaleConnectionStatus.error,
        errorMessage: 'Le moteur Tailscale est introuvable.',
      );
    }
  }

  /// Traite un événement JSON reçu du daemon
  void _handleEvent(String jsonLine) {
    try {
      final event = jsonDecode(jsonLine) as Map<String, dynamic>;
      final eventType = event['event'] as String?;

      switch (eventType) {
        case 'started':
          final backendState = event['state'] as String? ?? '';
          if (backendState == 'Running') {
            // Déjà connecté, demander le statut complet
            _sendCommand({'cmd': 'status'});
          } else {
            state = state.copyWith(status: TailscaleConnectionStatus.loggedOut);
          }

        case 'auth_url':
          final url = event['url'] as String?;
          if (url != null && url.isNotEmpty) {
            final uri = Uri.tryParse(url);
            if (uri != null && uri.scheme == 'https') {
              _openUrl(url);
            } else {
              debugPrint('[Tailscale] Auth URL invalide ignorée: $url');
            }
          }

        case 'connected':
        case 'status':
          final backendState = event['state'] as String? ?? 'Running';
          if (backendState == 'Running') {
            final selfHostname = event['self_hostname'] as String?;
            final selfIp = event['self_ip'] as String?;
            final peersJson = event['peers'] as List<dynamic>? ?? [];
            final peers = peersJson
                .map(_parsePeer)
                .whereType<TailscalePeer>()
                .toList();

            state = state.copyWith(
              status: TailscaleConnectionStatus.connected,
              selfHostname: selfHostname,
              selfIp: selfIp,
              peers: peers,
              isLoggingIn: false,
            );
            _startPolling();
          } else {
            state = state.copyWith(
              status: TailscaleConnectionStatus.loggedOut,
              isLoggingIn: false,
            );
          }

        case 'logged_out':
          _stopPolling();
          state = state.copyWith(
            status: TailscaleConnectionStatus.loggedOut,
            selfHostname: null,
            selfIp: null,
            peers: [],
            isLoggingIn: false,
          );

        case 'error':
          final message = event['message'] as String? ?? 'Erreur inconnue';
          state = state.copyWith(errorMessage: message, isLoggingIn: false);
      }
    } catch (e) {
      debugPrint('Chill: JSON parse error: $e');
    }
  }

  /// Appelé quand le daemon crash ou se ferme
  void _onDaemonCrash() {
    _stopPolling();
    if (state.status != TailscaleConnectionStatus.error) {
      state = state.copyWith(
        status: TailscaleConnectionStatus.error,
        errorMessage: 'Le moteur Tailscale s\'est arrêté.',
        isLoggingIn: false,
      );
    }
  }

  /// Déclenche le login OAuth (ouvre le navigateur)
  Future<void> login() async {
    state = state.copyWith(isLoggingIn: true, errorMessage: null);
    _sendCommand({'cmd': 'login'});
  }

  /// Déconnecte du réseau Tailscale
  Future<void> logout() async {
    state = state.copyWith(errorMessage: null);
    _sendCommand({'cmd': 'logout'});
  }

  /// Relance le daemon après une erreur
  Future<void> retry() async {
    if (_isRetrying) return;
    _isRetrying = true;
    try {
      if (_daemon != null) {
        final process = _daemon!;
        _daemon = null;
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () => -1,
        );
      }
      _stopPolling();
      await _startDaemon();
    } finally {
      _isRetrying = false;
    }
  }

  /// Demande un rafraîchissement du statut
  Future<void> refreshStatus() async {
    _sendCommand({'cmd': 'status'});
  }

  /// Envoie une commande JSON au daemon via stdin
  void _sendCommand(Map<String, dynamic> cmd) {
    if (_daemon != null) {
      _daemon!.stdin.writeln(jsonEncode(cmd));
    }
  }

  /// Ouvre une URL dans le navigateur système
  Future<void> _openUrl(String url) async {
    // Validation : accepter uniquement HTTPS
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      debugPrint('[Tailscale] URL rejetée (non-HTTPS): $url');
      return;
    }

    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [url]);
      if (result.exitCode != 0) {
        debugPrint(
          '[Tailscale] Failed to open URL (exit ${result.exitCode}): ${result.stderr}',
        );
      }
    } else if (Platform.isWindows) {
      // Le string vide comme titre empêche l'injection via caractères spéciaux dans l'URL
      final result = await Process.run('cmd', ['/c', 'start', '', url]);
      if (result.exitCode != 0) {
        debugPrint(
          '[Tailscale] Failed to open URL (exit ${result.exitCode}): ${result.stderr}',
        );
      }
    } else if (Platform.isMacOS) {
      final result = await Process.run('open', [url]);
      if (result.exitCode != 0) {
        debugPrint(
          '[Tailscale] Failed to open URL (exit ${result.exitCode}): ${result.stderr}',
        );
      }
    }
  }

  /// Démarre le polling du statut toutes les 10 secondes
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _sendCommand({'cmd': 'status'});
    });
  }

  /// Arrête le polling
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Parse un peer JSON de manière robuste, retourne null si invalide
  TailscalePeer? _parsePeer(dynamic p) {
    try {
      final peer = p as Map<String, dynamic>;
      return TailscalePeer(
        hostname: (peer['hostname'] as String?) ?? 'Unknown',
        ipv4: (peer['ip'] as String?) ?? '',
        os: (peer['os'] as String?) ?? '',
        isOnline: peer['online'] == true,
      );
    } catch (e) {
      debugPrint('[Tailscale] Invalid peer data: $e');
      return null;
    }
  }

  /// Arrête le daemon proprement
  void _shutdownDaemon() {
    _stopPolling();
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    if (_daemon != null) {
      final process = _daemon!;
      _daemon = null;
      try {
        // Envoyer la commande shutdown
        process.stdin.writeln(jsonEncode({'cmd': 'shutdown'}));
        // Laisser le daemon se fermer proprement (max 3s)
        unawaited(
          process.exitCode.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              process.kill();
              return -1;
            },
          ),
        );
      } catch (e) {
        debugPrint('[Tailscale] Shutdown error: $e');
        process.kill();
      }
    }
  }
}
