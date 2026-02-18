// Tests unitaires pour FIX-041 — Honeypot SSH
// Lance avec : flutter test test/unit/security/test_honeypot_ssh.dart
//
// Les tests couvrent la logique pure (HoneypotEvent, banniere, limites,
// journal) sans ouvrir de vrai socket reseau.

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/honeypot_ssh.dart';

void main() {
  // ===========================================================================
  // HoneypotEvent — serialisation
  // ===========================================================================

  group('HoneypotEvent — serialisation toJson', () {
    test('tous les champs sont serialises correctement', () {
      final ts = DateTime.utc(2026, 2, 18, 15, 0, 0);
      final event = HoneypotEvent(
        sourceIp: '192.168.1.100',
        sourcePort: 45678,
        timestamp: ts,
        clientBanner: 'SSH-2.0-OpenSSH_9.0',
        username: 'root',
        sessionDuration: const Duration(seconds: 42),
      );

      final json = event.toJson();
      expect(json['source_ip'], '192.168.1.100');
      expect(json['source_port'], 45678);
      expect(json['timestamp'], '2026-02-18T15:00:00.000Z');
      expect(json['client_banner'], 'SSH-2.0-OpenSSH_9.0');
      expect(json['username'], 'root');
      expect(json['session_duration_ms'], 42000);
    });

    test('champs optionnels null sont serialises comme null', () {
      final event = HoneypotEvent(
        sourceIp: '10.0.0.1',
        sourcePort: 22,
        timestamp: DateTime.now(),
        sessionDuration: Duration.zero,
      );

      final json = event.toJson();
      expect(json['client_banner'], isNull);
      expect(json['username'], isNull);
    });

    test('session_duration_ms est bien en millisecondes', () {
      final event = HoneypotEvent(
        sourceIp: '10.0.0.1',
        sourcePort: 22,
        timestamp: DateTime(2026),
        sessionDuration: const Duration(minutes: 2, seconds: 30),
      );

      // 2min30s = 150 000 ms
      expect(event.toJson()['session_duration_ms'], 150000);
    });

    test('duree zero est serialisee a 0', () {
      final event = HoneypotEvent(
        sourceIp: '127.0.0.1',
        sourcePort: 1234,
        timestamp: DateTime(2026),
        sessionDuration: Duration.zero,
      );

      expect(event.toJson()['session_duration_ms'], 0);
    });
  });

  // ===========================================================================
  // SshHoneypot — configuration par defaut
  // ===========================================================================

  group('SshHoneypot — configuration par defaut', () {
    test('port par defaut est 22', () {
      final honeypot = SshHoneypot();
      expect(honeypot.port, 22);
    });

    test('banniere par defaut commence par SSH-2.0-OpenSSH', () {
      final honeypot = SshHoneypot();
      expect(honeypot.banner, startsWith('SSH-2.0-OpenSSH'));
    });

    test('maxConnections est 20 par defaut', () {
      final honeypot = SshHoneypot();
      expect(honeypot.maxConnections, 20);
    });

    test('le honeypot demarre comme non-running', () {
      final honeypot = SshHoneypot();
      expect(honeypot.isRunning, isFalse);
    });

    test('journal d evenements demarre vide', () {
      final honeypot = SshHoneypot();
      expect(honeypot.events, isEmpty);
    });
  });

  // ===========================================================================
  // SshHoneypot — configuration personnalisee
  // ===========================================================================

  group('SshHoneypot — configuration personnalisee', () {
    test('port 2222 est accepte', () {
      final honeypot = SshHoneypot(port: 2222);
      expect(honeypot.port, 2222);
    });

    test('maxConnections personnalise est respecte', () {
      final honeypot = SshHoneypot(maxConnections: 5);
      expect(honeypot.maxConnections, 5);
    });

    test('banniere personnalisee est respectee', () {
      const customBanner = 'SSH-2.0-dropbear_2022.83';
      final honeypot = SshHoneypot(banner: customBanner);
      expect(honeypot.banner, customBanner);
    });

    test('callback onAttacker est assigne', () {
      HoneypotEvent? captured;
      final honeypot = SshHoneypot(
        onAttacker: (event) => captured = event,
      );

      // Verifier que le callback est bien configure (pas encore appele)
      expect(captured, isNull);
      expect(honeypot.onAttacker, isNotNull);
    });
  });

  // ===========================================================================
  // SshHoneypot — validation de banniere
  // ===========================================================================

  group('SshHoneypot — validation du format de banniere SSH', () {
    test('banniere valide commence par SSH-2.0-', () {
      expect(SshHoneypot.isValidBanner('SSH-2.0-OpenSSH_8.9p1'), isTrue);
      expect(SshHoneypot.isValidBanner('SSH-2.0-dropbear_2022'), isTrue);
    });

    test('banniere invalide est rejetee', () {
      expect(SshHoneypot.isValidBanner('SSH-1.0-OldSSH'), isFalse);
      expect(SshHoneypot.isValidBanner('HTTP/1.1 200 OK'), isFalse);
      expect(SshHoneypot.isValidBanner(''), isFalse);
      expect(SshHoneypot.isValidBanner('SSH-2.0-'), isFalse);
    });

    test('banniere par defaut statique est valide', () {
      expect(SshHoneypot.isValidBanner(SshHoneypot.defaultBanner), isTrue);
    });

    test('differentes bannieres SSH-2.0 reelles sont valides', () {
      const banners = [
        'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
        'SSH-2.0-OpenSSH_9.6p1 Debian-1',
        'SSH-2.0-dropbear_2022.83',
        'SSH-2.0-libssh_0.9.6',
      ];
      for (final b in banners) {
        expect(SshHoneypot.isValidBanner(b), isTrue,
            reason: 'Banniere devrait etre valide: $b');
      }
    });
  });

  // ===========================================================================
  // SshHoneypot — gestion du journal d'evenements
  // ===========================================================================

  group('SshHoneypot — journal d evenements', () {
    test('clearEvents vide le journal', () {
      final honeypot = SshHoneypot();
      expect(honeypot.events, isEmpty);
      honeypot.clearEvents();
      expect(honeypot.events, isEmpty);
    });

    test('events retourne une liste immuable', () {
      final honeypot = SshHoneypot();
      final events = honeypot.events;
      final fakeEvent = HoneypotEvent(
        sourceIp: '1.2.3.4',
        sourcePort: 22,
        timestamp: DateTime.now(),
        sessionDuration: Duration.zero,
      );
      expect(() => events.add(fakeEvent), throwsUnsupportedError);
    });

    test('maxEventLog est 10000', () {
      expect(SshHoneypot.maxEventLog, 10000);
    });
  });

  // ===========================================================================
  // SshHoneypot — statistiques
  // ===========================================================================

  group('SshHoneypot — statistiques', () {
    test('stats contient les cles attendues', () {
      final honeypot = SshHoneypot(port: 2222, maxConnections: 10);
      final s = honeypot.stats;

      expect(s.containsKey('is_running'), isTrue);
      expect(s.containsKey('active_connections'), isTrue);
      expect(s.containsKey('total_events'), isTrue);
      expect(s.containsKey('port'), isTrue);
      expect(s.containsKey('max_connections'), isTrue);
    });

    test('stats.port correspond au port configure', () {
      final honeypot = SshHoneypot(port: 2222);
      expect(honeypot.stats['port'], 2222);
    });

    test('stats.max_connections correspond a la limite', () {
      final honeypot = SshHoneypot(maxConnections: 15);
      expect(honeypot.stats['max_connections'], 15);
    });

    test('stats.is_running est false avant demarrage', () {
      final honeypot = SshHoneypot();
      expect(honeypot.stats['is_running'], isFalse);
    });
  });

  // ===========================================================================
  // SshHoneypot — start avec binder injecte (sans vrai socket)
  // ===========================================================================

  group('SshHoneypot — demarrage avec binder qui echoue', () {
    test('start retourne false quand le bind echoue', () async {
      final honeypot = SshHoneypot(
        port: 22,
        binder: (addr, port) async => throw Exception('Permission denied'),
      );

      final result = await honeypot.start();
      expect(result, isFalse);
      expect(honeypot.isRunning, isFalse);
    });
  });
}
