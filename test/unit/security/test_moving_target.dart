// Test unitaire pour FIX-047/048 — MovingTargetDefense + AttackerFingerprinter
// Lance avec : flutter test test/unit/security/test_moving_target.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/moving_target.dart';

void main() {
  group('MovingTargetConfig — configuration', () {
    test('Valeurs par defaut correctes', () {
      const config = MovingTargetConfig();
      expect(config.basePort, equals(22));
      expect(config.portRangeStart, equals(49152));
      expect(config.portRangeEnd, equals(65535));
      expect(config.portLifetime, equals(const Duration(hours: 6)));
    });

    test('Valeurs personnalisees sont correctement stockees', () {
      const config = MovingTargetConfig(
        basePort: 2222,
        portRangeStart: 50000,
        portRangeEnd: 60000,
        portLifetime: Duration(hours: 1),
      );
      expect(config.basePort, equals(2222));
      expect(config.portRangeStart, equals(50000));
      expect(config.portRangeEnd, equals(60000));
    });
  });

  group('MovingTargetDefense — port hopping', () {
    test('Le port initial est dans la plage configuree', () {
      final mtd = MovingTargetDefense();
      expect(mtd.currentPort, greaterThanOrEqualTo(49152));
      expect(mtd.currentPort, lessThan(65535));
    });

    test('Port dans une plage personnalisee', () {
      final mtd = MovingTargetDefense(
        config: const MovingTargetConfig(
          portRangeStart: 50000,
          portRangeEnd: 51000,
        ),
      );
      expect(mtd.currentPort, greaterThanOrEqualTo(50000));
      expect(mtd.currentPort, lessThan(51000));
    });

    test('needsRotation retourne false au demarrage', () {
      final mtd = MovingTargetDefense();
      expect(mtd.needsRotation, isFalse);
    });

    test('needsRotation retourne true quand la duree est depassee', () async {
      final mtd = MovingTargetDefense(
        config: const MovingTargetConfig(
          portLifetime: Duration(milliseconds: 5),
        ),
      );
      // Attendre que le delai expire
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mtd.needsRotation, isTrue);
    });

    test('lastRotation est initialise recemment', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final mtd = MovingTargetDefense();
      expect(mtd.lastRotation.isAfter(before), isTrue);
    });
  });

  group('MovingTargetDefense — randomBanner()', () {
    test('randomBanner retourne une banniere SSH valide', () {
      final banner = MovingTargetDefense.randomBanner();
      expect(banner, startsWith('SSH-2.0-'));
    });

    test('randomBanner retourne des valeurs variees', () {
      // Sur plusieurs appels, on doit obtenir au moins 2 bannieres differentes
      final banners = <String>{};
      for (int i = 0; i < 50; i++) {
        banners.add(MovingTargetDefense.randomBanner());
      }
      // Avec 6 bannieres et 50 appels, on attend plus d'une banniere unique
      expect(banners.length, greaterThan(1));
    });

    test('randomBanner contient un version SSH 2.0', () {
      final banner = MovingTargetDefense.randomBanner();
      expect(banner, contains('SSH-2.0'));
    });
  });

  group('AttackerProfile — profil d\'attaquant', () {
    test('Profil initialise avec des valeurs par defaut', () {
      final profile = AttackerProfile(sourceIp: '1.2.3.4');
      expect(profile.sourceIp, equals('1.2.3.4'));
      expect(profile.attemptCount, equals(0));
      expect(profile.banners, isEmpty);
      expect(profile.usernames, isEmpty);
      expect(profile.targetPorts, isEmpty);
    });

    test('firstSeen et lastSeen sont initialises', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final profile = AttackerProfile(sourceIp: '5.6.7.8');
      expect(profile.firstSeen.isAfter(before), isTrue);
      expect(profile.lastSeen.isAfter(before), isTrue);
    });
  });

  group('AttackerFingerprinter — fingerprinting', () {
    late AttackerFingerprinter fingerprinter;

    setUp(() {
      fingerprinter = AttackerFingerprinter();
    });

    test('Initialement aucun profil', () {
      expect(fingerprinter.profileCount, equals(0));
    });

    test('recordAttempt cree un nouveau profil', () {
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      expect(fingerprinter.profileCount, equals(1));
    });

    test('recordAttempt incremente le compteur pour une IP existante', () {
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      expect(fingerprinter.profileCount, equals(1));
      final profile = fingerprinter.getMostActive().first;
      expect(profile.attemptCount, equals(3));
    });

    test('recordAttempt cree des profils distincts pour des IPs differentes', () {
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      fingerprinter.recordAttempt(sourceIp: '10.0.0.2');
      expect(fingerprinter.profileCount, equals(2));
    });

    test('recordAttempt enregistre la banniere', () {
      fingerprinter.recordAttempt(
        sourceIp: '10.0.0.1',
        clientBanner: 'SSH-2.0-libssh_0.9.6',
      );
      final profile = fingerprinter.getMostActive().first;
      expect(profile.banners, contains('SSH-2.0-libssh_0.9.6'));
    });

    test('recordAttempt enregistre le username', () {
      fingerprinter.recordAttempt(
        sourceIp: '10.0.0.1',
        username: 'root',
      );
      final profile = fingerprinter.getMostActive().first;
      expect(profile.usernames, contains('root'));
    });

    test('recordAttempt enregistre le port cible', () {
      fingerprinter.recordAttempt(
        sourceIp: '10.0.0.1',
        port: 22,
      );
      final profile = fingerprinter.getMostActive().first;
      expect(profile.targetPorts, contains(22));
    });

    test('getMostActive retourne au maximum N profils', () {
      for (int i = 0; i < 15; i++) {
        fingerprinter.recordAttempt(sourceIp: '10.0.0.$i');
      }
      expect(fingerprinter.getMostActive(limit: 10), hasLength(10));
    });

    test('getMostActive trie par ordre decroissant de tentatives', () {
      fingerprinter.recordAttempt(sourceIp: '1.1.1.1');
      for (int i = 0; i < 5; i++) {
        fingerprinter.recordAttempt(sourceIp: '2.2.2.2');
      }
      fingerprinter.recordAttempt(sourceIp: '3.3.3.3');
      fingerprinter.recordAttempt(sourceIp: '3.3.3.3');

      final top = fingerprinter.getMostActive();
      expect(top.first.sourceIp, equals('2.2.2.2'));
      expect(top.first.attemptCount, equals(5));
    });

    test('cleanup supprime les profils anciens', () {
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      expect(fingerprinter.profileCount, equals(1));

      // Nettoyage avec une duree maximale de 0 secondes
      fingerprinter.cleanup(maxAge: Duration.zero);
      expect(fingerprinter.profileCount, equals(0));
    });

    test('cleanup conserve les profils recents', () {
      fingerprinter.recordAttempt(sourceIp: '10.0.0.1');
      fingerprinter.cleanup(maxAge: const Duration(days: 7));
      // Le profil vient d'etre cree, il ne doit pas etre supprime
      expect(fingerprinter.profileCount, equals(1));
    });
  });

  group('AttackerAnalysis — analyse des menaces', () {
    late AttackerFingerprinter fingerprinter;

    setUp(() {
      fingerprinter = AttackerFingerprinter();
    });

    test('Botnet detecte : > 100 tentatives, <= 2 bannieres', () {
      for (int i = 0; i < 101; i++) {
        fingerprinter.recordAttempt(
          sourceIp: '5.5.5.5',
          clientBanner: 'SSH-2.0-libssh_0.9.6',
        );
      }
      final profile = fingerprinter.getMostActive().first;
      final analysis = fingerprinter.analyze(profile);

      expect(analysis.likelyBotnet, isTrue);
      expect(analysis.threatLevel, equals('MEDIUM'));
    });

    test('Scanner detecte : > 5 ports differents cibles', () {
      for (int port in [22, 23, 8022, 2222, 222, 10022]) {
        fingerprinter.recordAttempt(sourceIp: '6.6.6.6', port: port);
      }
      final profile = fingerprinter.getMostActive().first;
      final analysis = fingerprinter.analyze(profile);

      expect(analysis.likelyScanner, isTrue);
      expect(analysis.threatLevel, equals('LOW'));
    });

    test('Attaque ciblee detectee : username non-generique', () {
      fingerprinter.recordAttempt(
        sourceIp: '7.7.7.7',
        username: 'kevin',
      );
      final profile = fingerprinter.getMostActive().first;
      final analysis = fingerprinter.analyze(profile);

      expect(analysis.likelyTargeted, isTrue);
      expect(analysis.threatLevel, equals('HIGH'));
    });

    test('Niveau INFO pour un profil neutre', () {
      fingerprinter.recordAttempt(
        sourceIp: '8.8.8.8',
        username: 'root',
        port: 22,
      );
      final profile = fingerprinter.getMostActive().first;
      final analysis = fingerprinter.analyze(profile);

      expect(analysis.likelyBotnet, isFalse);
      expect(analysis.likelyScanner, isFalse);
      expect(analysis.likelyTargeted, isFalse);
      expect(analysis.threatLevel, equals('INFO'));
    });
  });
}
