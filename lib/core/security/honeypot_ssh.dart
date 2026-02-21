// FIX-041 : Honeypot SSH
// GAP-041: Honeypots SSH absents (P2)
// Detecte et ralentit les attaquants avec un faux serveur SSH.
//
// Architecture testable : ServerSocket est injecte via un typedef pour
// permettre les tests unitaires sans ouvrir de vrai port reseau.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Tentative de connexion sur le honeypot.
class HoneypotEvent {
  final String sourceIp;
  final int sourcePort;
  final DateTime timestamp;
  final String? clientBanner;
  final String? username;
  final Duration sessionDuration;

  const HoneypotEvent({
    required this.sourceIp,
    required this.sourcePort,
    required this.timestamp,
    this.clientBanner,
    this.username,
    required this.sessionDuration,
  });

  Map<String, dynamic> toJson() => {
        'source_ip': sourceIp,
        'source_port': sourcePort,
        'timestamp': timestamp.toIso8601String(),
        'client_banner': clientBanner,
        'username': username,
        'session_duration_ms': sessionDuration.inMilliseconds,
      };

  @override
  String toString() =>
      'HoneypotEvent($sourceIp:$sourcePort banner=$clientBanner '
      'duration=${sessionDuration.inSeconds}s)';
}

/// Callback declenche quand un attaquant tombe dans le honeypot.
typedef HoneypotCallback = void Function(HoneypotEvent event);

/// Fonction d'injection pour creer un ServerSocket (permet les tests).
typedef ServerSocketBinder = Future<ServerSocket> Function(
  dynamic address,
  int port,
);

/// Honeypot SSH — faux serveur qui ralentit et logue les attaquants.
///
/// Envoie la banniere SSH byte par byte avec un delai (tarpit) pour
/// consommer les ressources de l'attaquant. Toutes les connexions sont
/// loguees comme [HoneypotEvent].
class SshHoneypot {
  final int port;
  final String banner;
  final Duration byteDelay;
  final int maxConnections;
  final ServerSocketBinder? _binder;

  ServerSocket? _server;
  final List<Socket> _activeConnections = [];
  final List<HoneypotEvent> _eventLog = [];

  /// Appelee a chaque nouvelle connexion d'attaquant loguee.
  HoneypotCallback? onAttacker;

  /// Nombre maximum d'evenements conserves en memoire.
  static const int maxEventLog = 10000;

  SshHoneypot({
    this.port = 22,
    this.banner = 'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
    this.byteDelay = const Duration(seconds: 10),
    this.maxConnections = 20,
    this.onAttacker,
    ServerSocketBinder? binder,
  }) : _binder = binder;

  /// Demarre le honeypot. Retourne true si le bind a reussi.
  Future<bool> start() async {
    try {
      final bind = _binder ?? ServerSocket.bind;
      _server = await bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleConnection, onError: (_) {});
      return true;
    } catch (_) {
      // Port < 1024 peut necessiter des privileges root.
      return false;
    }
  }

  /// Arrete le honeypot et ferme toutes les connexions actives.
  Future<void> stop() async {
    for (final conn in _activeConnections) {
      try {
        conn.destroy();
      } catch (_) {}
    }
    _activeConnections.clear();
    await _server?.close();
    _server = null;
  }

  /// Vrai si le honeypot est en cours d'ecoute.
  bool get isRunning => _server != null;

  /// Liste immuable des evenements enregistres.
  List<HoneypotEvent> get events => List.unmodifiable(_eventLog);

  /// Vide le journal d'evenements.
  void clearEvents() => _eventLog.clear();

  // ---------------------------------------------------------------------------
  // Gestion d'une connexion entrante
  // ---------------------------------------------------------------------------

  Future<void> _handleConnection(Socket socket) async {
    // Verifier la limite de connexions simultanees.
    if (_activeConnections.length >= maxConnections) {
      socket.destroy();
      return;
    }

    _activeConnections.add(socket);
    final startTime = DateTime.now();
    String? clientBanner;

    try {
      // 1. Envoyer la banniere SSH octet par octet (tarpit).
      final bannerBytes = utf8.encode('$banner\r\n');
      for (final byte in bannerBytes) {
        socket.add([byte]);
        await Future.delayed(byteDelay);
      }

      // 2. Lire la banniere du client (avec timeout de securite).
      try {
        final data = await socket.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () => Uint8List(0),
        );
        if (data.isNotEmpty) {
          clientBanner = utf8.decode(data, allowMalformed: true).trim();
        }
      } catch (_) {}

      // 3. Envoyer des donnees aleatoires pour simuler le KEX
      //    et epuiser les ressources de l'attaquant.
      final random = Random.secure();
      for (int i = 0; i < 100; i++) {
        try {
          socket.add([random.nextInt(256)]);
          await Future.delayed(byteDelay);
        } catch (_) {
          break;
        }
      }
    } catch (_) {
      // Connexion fermee par l'attaquant — normal.
    } finally {
      final duration = DateTime.now().difference(startTime);

      final event = HoneypotEvent(
        sourceIp: socket.remoteAddress.address,
        sourcePort: socket.remotePort,
        timestamp: startTime,
        clientBanner: clientBanner,
        sessionDuration: duration,
      );

      _eventLog.add(event);
      // Eviter l'epuisement memoire.
      if (_eventLog.length > maxEventLog) {
        _eventLog.removeAt(0);
      }

      onAttacker?.call(event);

      _activeConnections.remove(socket);
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Utilitaires de banniere
  // ---------------------------------------------------------------------------

  /// Verifie qu'une banniere respecte le format SSH-2.0-* RFC 4253.
  static bool isValidBanner(String banner) {
    return banner.startsWith('SSH-2.0-') && banner.length > 8;
  }

  /// Retourne la banniere par defaut (OpenSSH 8.9p1 Ubuntu).
  static String get defaultBanner => 'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7';

  /// Statistiques du honeypot.
  Map<String, dynamic> get stats => {
        'is_running': isRunning,
        'active_connections': _activeConnections.length,
        'total_events': _eventLog.length,
        'port': port,
        'max_connections': maxConnections,
      };
}
