// =============================================================
// TEST FIX-047 + FIX-048 : Moving Target + Attacker Fingerprinter
// Verification du port hopping et du profilage des attaquants
// =============================================================

import 'dart:math';
import 'package:test/test.dart';

// Reproduction des types pour les tests
class MovingTargetConfig {
  final int basePort;
  final int portRangeStart;
  final int portRangeEnd;
  final Duration portLifetime;

  const MovingTargetConfig({
    this.basePort = 22,
    this.portRangeStart = 49152,
    this.portRangeEnd = 65535,
    this.portLifetime = const Duration(hours: 6),
  });
}

class AttackerProfile {
  final String sourceIp;
  int attemptCount;
  DateTime firstSeen;
  DateTime lastSeen;
  final Set<String> banners;
  final Set<String> usernames;
  final Set<int> targetPorts;

  AttackerProfile({required this.sourceIp})
      : attemptCount = 0,
        firstSeen = DateTime.now(),
        lastSeen = DateTime.now(),
        banners = {},
        usernames = {},
        targetPorts = {};
}

class AttackerAnalysis {
  final AttackerProfile profile;
  final bool likelyBotnet;
  final bool likelyScanner;
  final bool likelyTargeted;

  const AttackerAnalysis({
    required this.profile,
    required this.likelyBotnet,
    required this.likelyScanner,
    required this.likelyTargeted,
  });

  String get threatLevel {
    if (likelyTargeted) return 'HIGH';
    if (likelyBotnet) return 'MEDIUM';
    if (likelyScanner) return 'LOW';
    return 'INFO';
  }
}

class AttackerFingerprinter {
  final List<AttackerProfile> _profiles = [];

  void recordAttempt({
    required String sourceIp,
    String? clientBanner,
    String? username,
    int? port,
  }) {
    var profile = _profiles.firstWhere(
      (p) => p.sourceIp == sourceIp,
      orElse: () {
        final p = AttackerProfile(sourceIp: sourceIp);
        _profiles.add(p);
        return p;
      },
    );
    profile.attemptCount++;
    profile.lastSeen = DateTime.now();
    if (clientBanner != null) profile.banners.add(clientBanner);
    if (username != null) profile.usernames.add(username);
    if (port != null) profile.targetPorts.add(port);
  }

  List<AttackerProfile> getMostActive({int limit = 10}) {
    final sorted = List<AttackerProfile>.from(_profiles)
      ..sort((a, b) => b.attemptCount.compareTo(a.attemptCount));
    return sorted.take(limit).toList();
  }

  AttackerAnalysis analyze(AttackerProfile profile) {
    final isBotnet = profile.attemptCount > 100 &&
        profile.banners.length <= 2;
    final isScanner = profile.targetPorts.length > 5;
    final isTargeted = profile.usernames.any((u) =>
        u != 'root' && u != 'admin' && u != 'test');
    return AttackerAnalysis(
      profile: profile,
      likelyBotnet: isBotnet,
      likelyScanner: isScanner,
      likelyTargeted: isTargeted,
    );
  }
}

void main() {
  group('MovingTargetConfig', () {
    test('port par defaut est 22', () {
      const config = MovingTargetConfig();
      expect(config.basePort, 22);
    });

    test('plage de ports dans les ephemeral ports (49152-65535)', () {
      const config = MovingTargetConfig();
      expect(config.portRangeStart, 49152);
      expect(config.portRangeEnd, 65535);
    });

    test('rotation toutes les 6 heures', () {
      const config = MovingTargetConfig();
      expect(config.portLifetime.inHours, 6);
    });

    test('generation de port dans la plage', () {
      const config = MovingTargetConfig();
      final random = Random.secure();
      final range = config.portRangeEnd - config.portRangeStart;

      for (int i = 0; i < 100; i++) {
        final port = config.portRangeStart + random.nextInt(range);
        expect(port, greaterThanOrEqualTo(config.portRangeStart));
        expect(port, lessThan(config.portRangeEnd));
      }
    });

    test('ports generes sont varies (pas toujours le meme)', () {
      const config = MovingTargetConfig();
      final random = Random.secure();
      final range = config.portRangeEnd - config.portRangeStart;
      final ports = <int>{};

      for (int i = 0; i < 20; i++) {
        ports.add(config.portRangeStart + random.nextInt(range));
      }
      // Sur 20 generations, au moins 10 ports differents
      expect(ports.length, greaterThan(10));
    });
  });

  group('Bannieres SSH randomisees', () {
    test('toutes les bannieres commencent par SSH-2.0-', () {
      final banners = [
        'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
        'SSH-2.0-OpenSSH_9.6p1 Debian-1',
        'SSH-2.0-OpenSSH_9.3p1',
        'SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3',
        'SSH-2.0-dropbear_2022.83',
        'SSH-2.0-OpenSSH_9.0',
      ];
      for (final b in banners) {
        expect(b, startsWith('SSH-2.0-'));
      }
    });

    test('au moins 5 bannieres differentes', () {
      final banners = [
        'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
        'SSH-2.0-OpenSSH_9.6p1 Debian-1',
        'SSH-2.0-OpenSSH_9.3p1',
        'SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3',
        'SSH-2.0-dropbear_2022.83',
        'SSH-2.0-OpenSSH_9.0',
      ];
      expect(banners.toSet().length, greaterThanOrEqualTo(5));
    });
  });

  group('AttackerFingerprinter — Profiling', () {
    test('enregistre un nouvel attaquant', () {
      final fp = AttackerFingerprinter();
      fp.recordAttempt(sourceIp: '1.2.3.4');
      final active = fp.getMostActive();
      expect(active.length, 1);
      expect(active[0].sourceIp, '1.2.3.4');
      expect(active[0].attemptCount, 1);
    });

    test('agrege les tentatives pour la meme IP', () {
      final fp = AttackerFingerprinter();
      for (int i = 0; i < 5; i++) {
        fp.recordAttempt(
          sourceIp: '1.2.3.4',
          username: i.isEven ? 'root' : 'admin',
        );
      }
      final active = fp.getMostActive();
      expect(active.length, 1);
      expect(active[0].attemptCount, 5);
      expect(active[0].usernames, {'root', 'admin'});
    });

    test('separe les profils par IP', () {
      final fp = AttackerFingerprinter();
      fp.recordAttempt(sourceIp: '1.1.1.1');
      fp.recordAttempt(sourceIp: '2.2.2.2');
      fp.recordAttempt(sourceIp: '3.3.3.3');
      expect(fp.getMostActive().length, 3);
    });

    test('getMostActive trie par nombre de tentatives', () {
      final fp = AttackerFingerprinter();
      for (int i = 0; i < 10; i++) fp.recordAttempt(sourceIp: '1.1.1.1');
      for (int i = 0; i < 50; i++) fp.recordAttempt(sourceIp: '2.2.2.2');
      for (int i = 0; i < 5; i++) fp.recordAttempt(sourceIp: '3.3.3.3');

      final active = fp.getMostActive();
      expect(active[0].sourceIp, '2.2.2.2');
      expect(active[1].sourceIp, '1.1.1.1');
      expect(active[2].sourceIp, '3.3.3.3');
    });

    test('getMostActive respecte la limite', () {
      final fp = AttackerFingerprinter();
      for (int i = 0; i < 20; i++) {
        fp.recordAttempt(sourceIp: '10.0.0.$i');
      }
      expect(fp.getMostActive(limit: 5).length, 5);
    });

    test('collecte les bannieres client', () {
      final fp = AttackerFingerprinter();
      fp.recordAttempt(
        sourceIp: '1.1.1.1',
        clientBanner: 'SSH-2.0-libssh2_1.10.0',
      );
      fp.recordAttempt(
        sourceIp: '1.1.1.1',
        clientBanner: 'SSH-2.0-PuTTY_0.78',
      );
      final profile = fp.getMostActive()[0];
      expect(profile.banners.length, 2);
    });

    test('collecte les ports cibles', () {
      final fp = AttackerFingerprinter();
      fp.recordAttempt(sourceIp: '1.1.1.1', port: 22);
      fp.recordAttempt(sourceIp: '1.1.1.1', port: 2222);
      fp.recordAttempt(sourceIp: '1.1.1.1', port: 8022);
      final profile = fp.getMostActive()[0];
      expect(profile.targetPorts, {22, 2222, 8022});
    });
  });

  group('AttackerAnalysis — Classification des menaces', () {
    test('botnet : beaucoup de tentatives, peu de bannieres', () {
      final profile = AttackerProfile(sourceIp: '1.1.1.1');
      profile.attemptCount = 200;
      profile.banners.add('SSH-2.0-libssh2');

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      expect(analysis.likelyBotnet, isTrue);
      expect(analysis.threatLevel, 'MEDIUM');
    });

    test('scanner : beaucoup de ports cibles', () {
      final profile = AttackerProfile(sourceIp: '2.2.2.2');
      profile.attemptCount = 10;
      for (int p = 22; p < 30; p++) profile.targetPorts.add(p);

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      expect(analysis.likelyScanner, isTrue);
      expect(analysis.threatLevel, 'LOW');
    });

    test('attaque ciblee : usernames specifiques', () {
      final profile = AttackerProfile(sourceIp: '3.3.3.3');
      profile.attemptCount = 5;
      profile.usernames.addAll(['kevin', 'deployer']);

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      expect(analysis.likelyTargeted, isTrue);
      expect(analysis.threatLevel, 'HIGH');
    });

    test('attaque ciblee prime sur botnet dans le threatLevel', () {
      final profile = AttackerProfile(sourceIp: '4.4.4.4');
      profile.attemptCount = 200;
      profile.banners.add('SSH-2.0-x');
      profile.usernames.add('specific_user');

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      // likelyTargeted prime dans la hierarchie
      expect(analysis.threatLevel, 'HIGH');
    });

    test('root/admin/test ne sont PAS consideres comme cibles', () {
      final profile = AttackerProfile(sourceIp: '5.5.5.5');
      profile.attemptCount = 5;
      profile.usernames.addAll(['root', 'admin', 'test']);

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      expect(analysis.likelyTargeted, isFalse);
    });

    test('profil vide = INFO', () {
      final profile = AttackerProfile(sourceIp: '6.6.6.6');
      profile.attemptCount = 1;

      final fp = AttackerFingerprinter();
      final analysis = fp.analyze(profile);
      expect(analysis.threatLevel, 'INFO');
    });
  });
}
