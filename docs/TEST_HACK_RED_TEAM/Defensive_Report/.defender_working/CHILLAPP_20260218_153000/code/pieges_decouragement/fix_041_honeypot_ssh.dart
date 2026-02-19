// =============================================================
// FIX-041 : Honeypot SSH
// GAP-041: Honeypots SSH absents (P2)
// Cible: lib/core/security/honeypot_ssh.dart (nouveau)
// =============================================================
//
// PROBLEME : Aucun leurre SSH pour detecter et ralentir les
// attaquants. Le vrai SSH est directement expose.
//
// SOLUTION :
// 1. Faux serveur SSH sur port 22 (banner realistique)
// 2. Le vrai SSH sur un port randomise via Tailscale
// 3. Logger TOUTES les tentatives sur le honeypot
// 4. Reponses lentes (1 byte/10s) pour consommer les ressources
// =============================================================

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
}

/// Callback quand un attaquant tombe dans le honeypot.
typedef HoneypotCallback = void Function(HoneypotEvent event);

/// Honeypot SSH — faux serveur qui ralentit et logue les attaquants.
class SshHoneypot {
  final int port;
  final String banner;
  final Duration byteDelay;
  final int maxConnections;
  ServerSocket? _server;
  final List<Socket> _activeConnections = [];
  HoneypotCallback? onAttacker;
  final List<HoneypotEvent> _eventLog = [];

  SshHoneypot({
    this.port = 22,
    this.banner = 'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
    this.byteDelay = const Duration(seconds: 10),
    this.maxConnections = 20,
    this.onAttacker,
  });

  /// Demarre le honeypot.
  Future<bool> start() async {
    try {
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );

      _server!.listen(
        _handleConnection,
        onError: (_) {},
      );

      return true;
    } catch (e) {
      // Port 22 peut necessiter les privileges root
      return false;
    }
  }

  /// Arrete le honeypot.
  Future<void> stop() async {
    for (final conn in _activeConnections) {
      try { conn.destroy(); } catch (_) {}
    }
    _activeConnections.clear();
    await _server?.close();
    _server = null;
  }

  /// Log des evenements.
  List<HoneypotEvent> get events => List.unmodifiable(_eventLog);

  void _handleConnection(Socket socket) async {
    if (_activeConnections.length >= maxConnections) {
      socket.destroy();
      return;
    }

    _activeConnections.add(socket);
    final startTime = DateTime.now();
    String? clientBanner;

    try {
      // 1. Envoyer la banniere SSH tres lentement (tarpit)
      final bannerBytes = utf8.encode('$banner\r\n');
      for (final byte in bannerBytes) {
        socket.add([byte]);
        await Future.delayed(byteDelay);
      }

      // 2. Lire la banniere du client (avec timeout)
      try {
        final data = await socket.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () => <int>[],
        );
        if (data.isNotEmpty) {
          clientBanner = utf8.decode(data, allowMalformed: true).trim();
        }
      } catch (_) {}

      // 3. Envoyer des donnees aleatoires pour simuler le KEX
      // (consomme du temps et des ressources de l'attaquant)
      final random = Random.secure();
      for (int i = 0; i < 100; i++) {
        final junk = List.generate(1, (_) => random.nextInt(256));
        try {
          socket.add(junk);
          await Future.delayed(byteDelay);
        } catch (_) {
          break;
        }
      }
    } catch (_) {
    } finally {
      final duration = DateTime.now().difference(startTime);

      // Logger l'evenement
      final event = HoneypotEvent(
        sourceIp: socket.remoteAddress.address,
        sourcePort: socket.remotePort,
        timestamp: startTime,
        clientBanner: clientBanner,
        sessionDuration: duration,
      );
      _eventLog.add(event);
      if (_eventLog.length > 10000) _eventLog.removeAt(0);

      onAttacker?.call(event);

      _activeConnections.remove(socket);
      try { socket.destroy(); } catch (_) {}
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Deployer le honeypot sur port 22 :
//    (necessite root/admin pour port < 1024)
//
//   final honeypot = SshHoneypot(
//     port: 22,
//     onAttacker: (event) {
//       auditLog.log(SecurityAction.honeypotTriggered,
//         'Attaquant: ${event.sourceIp} banner: ${event.clientBanner}');
//     },
//   );
//   await honeypot.start();
//
// 2. Le vrai SSH tourne sur un port aléatoire via Tailscale
//    (accessible uniquement depuis 100.64.0.0/10)
//
// 3. Alternative sans root : port 2222 avec redirection iptables
//   iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
// =============================================================
