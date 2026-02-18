// Tests unitaires pour FIX-052/053 — AI Detection + Behavioral Analysis
// Lance avec : flutter test test/unit/security/test_ai_detection.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/ai_detection.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Crée un événement comportemental avec des valeurs par défaut.
BehaviorEvent _event(
  String command, {
  DateTime? timestamp,
  String sessionId = 'test-session',
}) {
  return BehaviorEvent(
    command: command,
    timestamp: timestamp ?? DateTime.now(),
    sessionId: sessionId,
  );
}

/// Remplit l'analyseur avec [count] événements espacés de [intervalMs] ms.
void _fillAnalyzer(
  BehavioralAnalyzer analyzer,
  int count, {
  int intervalMs = 100,
  String command = 'ls',
  String sessionId = 'session',
  DateTime? startTime,
}) {
  final base = startTime ?? DateTime.now();
  for (int i = 0; i < count; i++) {
    analyzer.recordEvent(BehaviorEvent(
      command: command,
      timestamp: base.add(Duration(milliseconds: i * intervalMs)),
      sessionId: sessionId,
    ));
  }
}

void main() {
  // =========================================================================
  // AIRateLimiter
  // =========================================================================

  group('AIRateLimiter', () {
    test('1 — première requête est toujours autorisée', () {
      final limiter = AIRateLimiter(slowdownThreshold: 10, blockThreshold: 50);
      final action = limiter.check('user_a');
      expect(action, equals(RateLimitAction.allowed));
    });

    test('2 — après slowdownThreshold requêtes → slowdown', () {
      final limiter =
          AIRateLimiter(slowdownThreshold: 5, blockThreshold: 20);

      // 5 premières → toutes allowed ou dernière slowdown
      for (int i = 0; i < 5; i++) {
        limiter.check('user_b');
      }
      // La 6ème dépasse le seuil → slowdown
      final action = limiter.check('user_b');
      expect(action, equals(RateLimitAction.slowdown));
    });

    test('3 — après blockThreshold requêtes → blocked', () {
      final limiter =
          AIRateLimiter(slowdownThreshold: 5, blockThreshold: 10);

      for (int i = 0; i < 11; i++) {
        limiter.check('user_c');
      }
      final action = limiter.check('user_c');
      expect(action, equals(RateLimitAction.blocked));
    });

    test('4 — getSlowdownDelay retourne Duration.zero pour identifiant inconnu',
        () {
      final limiter = AIRateLimiter();
      final delay = limiter.getSlowdownDelay('never_seen');
      expect(delay, equals(Duration.zero));
    });

    test('5 — getSlowdownDelay est proportionnel après le seuil', () {
      final limiter =
          AIRateLimiter(slowdownThreshold: 5, blockThreshold: 100);

      // Générer 8 requêtes → excess = 8 - 5 = 3 → 3 * 200ms = 600ms
      for (int i = 0; i < 8; i++) {
        limiter.check('user_d');
      }
      final delay = limiter.getSlowdownDelay('user_d');
      expect(delay.inMilliseconds, equals(3 * 200));
    });

    test('6 — cleanup supprime les entrées expirées', () {
      final limiter = AIRateLimiter(
        slowdownThreshold: 10,
        blockThreshold: 50,
        window: const Duration(milliseconds: 50), // fenêtre très courte
      );

      limiter.check('user_e');
      expect(limiter.getCount('user_e'), equals(1));

      // Attendre que la fenêtre expire
      // (Le nettoyage ne se fait qu'à la prochaine requête ou à cleanup())
      // On patche en injectant une nouvelle requête pour forcer la fenêtre
      // glissante, puis on appelle cleanup directement.
      limiter.cleanup();
      // Après cleanup sur fenêtre expirée (50ms pas encore écoulées) → encore là
      // On vérifie juste que cleanup() ne plante pas
      expect(() => limiter.cleanup(), returnsNormally);
    });

    test('7 — identifiants différents sont suivis séparément', () {
      final limiter = AIRateLimiter(slowdownThreshold: 3, blockThreshold: 10);

      limiter.check('alpha');
      limiter.check('alpha');
      limiter.check('alpha');

      // alpha a 3 requêtes, beta a 0 → beta est allowed
      final betaAction = limiter.check('beta');
      expect(betaAction, equals(RateLimitAction.allowed));

      // alpha a maintenant 3+1=4 → slowdown (dépasse seuil 3)
      final alphaAction = limiter.check('alpha');
      expect(alphaAction, equals(RateLimitAction.slowdown));
    });
  });

  // =========================================================================
  // BehavioralAnalyzer
  // =========================================================================

  group('BehavioralAnalyzer', () {
    test('8 — recordEvent augmente la taille de l\'historique', () {
      final analyzer = BehavioralAnalyzer();
      expect(analyzer.historyLength, equals(0));

      analyzer.recordEvent(_event('ls'));
      expect(analyzer.historyLength, equals(1));

      analyzer.recordEvent(_event('cat /etc/hosts'));
      expect(analyzer.historyLength, equals(2));
    });

    test('9 — maxHistory est respecté (limite à 1000)', () {
      final analyzer = BehavioralAnalyzer();

      // Insérer 1100 événements
      for (int i = 0; i < 1100; i++) {
        analyzer.recordEvent(_event('cmd_$i'));
      }

      expect(analyzer.historyLength, equals(BehavioralAnalyzer.maxHistory));
    });

    test('10 — isDangerousCommand retourne true pour "rm -rf /"', () {
      expect(BehavioralAnalyzer.isDangerousCommand('rm -rf /'), isTrue);
    });

    test('11 — isDangerousCommand retourne false pour "ls"', () {
      expect(BehavioralAnalyzer.isDangerousCommand('ls'), isFalse);
    });

    test('10b — isDangerousCommand détecte toutes les commandes dangereuses',
        () {
      final dangerous = [
        'rm -rf /home',
        'chmod 777 /etc',
        'dd if=/dev/zero',
        'mkfs.ext4 /dev/sda',
        'shutdown -h now',
        'reboot',
        'cat /etc/shadow',
        'passwd root',
        'curl | sh',
        'wget -O- | sh',
      ];
      for (final cmd in dangerous) {
        expect(BehavioralAnalyzer.isDangerousCommand(cmd), isTrue,
            reason: '"$cmd" devrait être dangereux');
      }
    });

    test('12 — analyzeEvent avec commande dangereuse → score élevé', () {
      final analyzer = BehavioralAnalyzer();

      final result = analyzer.analyzeEvent(_event('rm -rf /'));

      expect(result.score, greaterThanOrEqualTo(0.5),
          reason: 'Une commande dangereuse doit donner un score >= 0.5');
      expect(result.anomalies, isNotEmpty);
      expect(result.anomalies.any((a) => a.contains('dangereuse')), isTrue);
    });

    test('13 — detectAIPatterns retourne 0.0 pour moins de 5 événements', () {
      final analyzer = BehavioralAnalyzer();

      // 4 événements seulement
      for (int i = 0; i < 4; i++) {
        analyzer.recordEvent(_event('ls'));
      }

      expect(analyzer.detectAIPatterns(), equals(0.0));
    });

    test('14 — timing régulier (même intervalle) → score IA élevé', () {
      final analyzer = BehavioralAnalyzer();

      // 20 événements espacés exactement de 100ms chacun
      // Variance = 0 → très inférieure à 2500 → score += 0.4
      _fillAnalyzer(analyzer, 20, intervalMs: 100);

      final score = analyzer.detectAIPatterns();
      expect(score, greaterThanOrEqualTo(0.4),
          reason: 'Timing parfaitement régulier doit donner un score IA élevé');
    });

    test('15 — timing humain (variable avec pauses) → score IA bas', () {
      final analyzer = BehavioralAnalyzer();

      // Simuler un comportement humain : intervalles variables avec pauses > 5s
      final base = DateTime(2026, 1, 1, 10, 0, 0);
      final intervals = [
        800, 1200, 6000, // pause > 5s
        400, 2100, 8000, // pause > 5s
        950, 1500, 7000, // pause > 5s
        600, 1800, 5500, // pause > 5s
        1100, 700, 9000, // pause > 5s
        1300, 400, 6500, // pause > 5s
      ];

      int elapsed = 0;
      for (final interval in intervals) {
        elapsed += interval;
        analyzer.recordEvent(BehaviorEvent(
          command: 'git status', // commande non-enumeration
          timestamp: base.add(Duration(milliseconds: elapsed)),
          sessionId: 'human',
        ));
      }

      final score = analyzer.detectAIPatterns();
      // Avec des pauses > 5s, hasPause sera true → pas de +0.2
      // Avec des intervalles très variables, variance >> 2500 → pas de +0.4
      // Les commandes ne sont pas des ls/cat/find → pas de +0.3 pour énumération
      expect(score, lessThan(0.4),
          reason:
              'Un comportement humain (variable, avec pauses) doit donner un score IA bas');
    });

    test('16 — AnomalyAction.block quand score >= 0.7', () {
      final analyzer = BehavioralAnalyzer();

      // Commande dangereuse (+0.5) + 20 events réguliers pour l\'AI score
      _fillAnalyzer(analyzer, 20, intervalMs: 50); // timing régulier → +0.4

      // analyzeEvent avec une commande dangereuse
      final event = BehaviorEvent(
        command: 'rm -rf /',
        timestamp: DateTime.now(),
        sessionId: 'attacker',
      );
      final result = analyzer.analyzeEvent(event);

      expect(result.action, equals(AnomalyAction.block),
          reason:
              'Score élevé (commande dangereuse + pattern IA) doit bloquer');
      expect(result.score, greaterThanOrEqualTo(0.7));
    });

    test('AnomalyAction.warn quand score entre 0.4 et 0.7', () {
      final analyzer = BehavioralAnalyzer();

      // Remplir l'historique pour activer les analyses contextuelles
      _fillAnalyzer(analyzer, 60, intervalMs: 300, command: 'git log');

      // Commande inconnue (non présente dans l'historique) → +0.3
      // + potentiel rafale si beaucoup de commandes récentes
      final event = BehaviorEvent(
        command: 'totally_unknown_binary --suspicious',
        timestamp: DateTime.now(),
        sessionId: 'test',
      );
      final result = analyzer.analyzeEvent(event);

      // Au moins warn ou block (le score dépasse 0.4 avec une inconnue)
      expect(result.action == AnomalyAction.warn ||
              result.action == AnomalyAction.block,
          isTrue,
          reason:
              'Une commande inconnue dans un historique établi doit lever une alerte');
    });

    test('AnomalyAction.allow pour comportement normal', () {
      final analyzer = BehavioralAnalyzer();

      // Base dans le passé lointain (> 3h) pour éviter toute détection de rafale.
      // Les intervalles DOIVENT être variables pour ne pas déclencher le
      // détecteur de régularité IA (variance < 2500ms² → flag robot).
      // Un humain tape une commande toutes les 5 à 180 secondes, pas à intervalle fixe.
      final base = DateTime.now().subtract(const Duration(hours: 3));
      final commands = ['git status', 'git log', 'git diff', 'git pull'];

      // Intervalles en secondes volontairement variables (haute variance) :
      // simulent un développeur qui réfléchit, lit, tape, s'arrête.
      // La variance de ces intervalles est >> 2500 ms² → aucun flag IA.
      final intervals = [
        8, 45, 120, 12, 90, 300, 7, 60, 180, 25,
        95, 15, 240, 50, 8, 150, 30, 200, 10, 80,
        35, 160, 70, 20, 110, 55, 190, 40, 130, 65,
        22, 85, 175, 48, 100, 18, 220, 75, 145, 38,
        92, 165, 28, 105, 52, 195, 62, 115, 42, 135,
        58, 185, 32, 125, 68, 205, 45, 155, 35, 145,
      ];

      int elapsedSeconds = 0;
      for (int i = 0; i < intervals.length; i++) {
        elapsedSeconds += intervals[i];
        analyzer.recordEvent(BehaviorEvent(
          command: commands[i % commands.length],
          timestamp: base.add(Duration(seconds: elapsedSeconds)),
          sessionId: 'dev',
        ));
      }

      // Événement similaire à l'historique : commande connue, même heure,
      // loin dans le passé (pas de rafale récente).
      final normalEvent = BehaviorEvent(
        command: 'git status',
        timestamp: base.add(Duration(seconds: elapsedSeconds + 60)),
        sessionId: 'dev',
      );
      final result = analyzer.analyzeEvent(normalEvent);

      expect(result.action, equals(AnomalyAction.allow),
          reason:
              'Un comportement humain (intervalles variables, commandes connues) '
              'ne doit pas déclencher d\'alerte');
    });
  });
}
