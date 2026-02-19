// =============================================================
// FIX-052 : Rate Limiting anti-agent IA
// GAP-052: Rate limiting anti-agent IA absent (P0)
// FIX-053 : Detection comportementale IA
// GAP-053: Detection comportementale IA absente (P1)
// Cible: lib/core/security/ai_detection.dart (nouveau)
// =============================================================
//
// PROBLEME GAP-052 : Un agent IA peut executer des milliers de
// requetes par seconde sans etre detecte (ref: GTG-1002).
//
// PROBLEME GAP-053 : Impossible de distinguer un humain d'un
// agent IA automatise.
//
// SOLUTION :
// 1. Rate limiting progressif (10/30/100 req/min)
// 2. Detection de patterns non-humains (timing, variance, systematisme)
// 3. Anomaly scoring multi-dimensionnel
// 4. Tout est local (pas de cloud)
// =============================================================

import 'dart:collection';
import 'dart:math';

/// Resultat du rate limiting.
enum RateLimitAction {
  /// Requete autorisee.
  allowed,

  /// Ralentir (delai ajoute).
  slowdown,

  /// Requete bloquee.
  blocked,
}

/// Rate limiter anti-agent IA avec seuils progressifs.
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

  /// Verifie si une requete doit etre ralentie/bloquee.
  RateLimitAction check(String identifier) {
    final now = DateTime.now();
    final history = _history.putIfAbsent(identifier, () => []);

    // Nettoyer les entrees hors fenetre
    history.removeWhere((t) => now.difference(t) > window);

    // Ajouter la requete courante
    history.add(now);

    if (history.length > blockThreshold) {
      return RateLimitAction.blocked;
    } else if (history.length > slowdownThreshold) {
      return RateLimitAction.slowdown;
    }
    return RateLimitAction.allowed;
  }

  /// Calcule le delai de ralentissement.
  Duration getSlowdownDelay(String identifier) {
    final history = _history[identifier];
    if (history == null) return Duration.zero;
    // Delai proportionnel au nombre de requetes
    final excess = history.length - slowdownThreshold;
    if (excess <= 0) return Duration.zero;
    return Duration(milliseconds: excess * 200); // 200ms par requete en trop
  }

  /// Nettoie toutes les entrees expirees.
  void cleanup() {
    final now = DateTime.now();
    _history.forEach((key, history) {
      history.removeWhere((t) => now.difference(t) > window);
    });
    _history.removeWhere((_, history) => history.isEmpty);
  }
}

/// Evenement comportemental.
class BehaviorEvent {
  final String command;
  final DateTime timestamp;
  final String sessionId;
  final Map<String, dynamic>? metadata;

  BehaviorEvent({
    required this.command,
    required this.timestamp,
    required this.sessionId,
    this.metadata,
  });
}

/// Resultat de l'analyse d'anomalie.
class AnomalyResult {
  final double score; // 0.0 = normal, 1.0 = certainement IA
  final List<String> anomalies;
  final AnomalyAction action;

  const AnomalyResult({
    required this.score,
    required this.anomalies,
    required this.action,
  });
}

/// Action recommandee suite a l'analyse.
enum AnomalyAction {
  allow,
  warn,
  block,
}

/// Analyseur comportemental pour detecter les agents IA.
class BehavioralAnalyzer {
  final Queue<BehaviorEvent> _history = Queue();
  final Map<String, int> _commandFrequency = {};
  final Map<int, int> _hourDistribution = {};
  static const int maxHistory = 1000;

  /// Enregistre un evenement.
  void recordEvent(BehaviorEvent event) {
    _history.addLast(event);
    if (_history.length > maxHistory) _history.removeFirst();

    _commandFrequency[event.command] =
        (_commandFrequency[event.command] ?? 0) + 1;
    _hourDistribution[event.timestamp.hour] =
        (_hourDistribution[event.timestamp.hour] ?? 0) + 1;
  }

  /// Analyse un evenement pour detecter les anomalies.
  AnomalyResult analyzeEvent(BehaviorEvent event) {
    final anomalies = <String>[];
    double score = 0.0;
    final totalEvents = _history.length;

    // 1. Horaire inhabituel
    if (totalEvents > 50) {
      final hourCount = _hourDistribution[event.timestamp.hour] ?? 0;
      if (hourCount < totalEvents * 0.02) {
        anomalies.add('Horaire inhabituel (${event.timestamp.hour}h)');
        score += 0.2;
      }
    }

    // 2. Commande jamais utilisee
    if (!_commandFrequency.containsKey(event.command) && totalEvents > 50) {
      anomalies.add('Commande inconnue: ${event.command}');
      score += 0.3;
    }

    // 3. Commandes dangereuses
    if (_isDangerousCommand(event.command)) {
      anomalies.add('Commande dangereuse');
      score += 0.5;
    }

    // 4. Rafale de commandes
    final recentCount = _history
        .where((e) => e.timestamp.isAfter(
            DateTime.now().subtract(const Duration(minutes: 1))))
        .length;
    if (recentCount > 10) {
      anomalies.add('Rafale: $recentCount commandes/min');
      score += 0.3;
    }

    // 5. Detection patterns IA specifiques
    final aiScore = _detectAIPatterns();
    if (aiScore > 0) {
      anomalies.add('Pattern agent IA detecte (score: ${aiScore.toStringAsFixed(2)})');
      score += aiScore;
    }

    score = score.clamp(0.0, 1.0);

    return AnomalyResult(
      score: score,
      anomalies: anomalies,
      action: score >= 0.7
          ? AnomalyAction.block
          : score >= 0.4
              ? AnomalyAction.warn
              : AnomalyAction.allow,
    );
  }

  /// Detecte les patterns specifiques aux agents IA.
  double _detectAIPatterns() {
    if (_history.length < 5) return 0.0;

    double score = 0.0;
    final events = _history.toList();

    // 1. Timing trop regulier (variance < 50ms)
    final intervals = <int>[];
    for (int i = 1; i < events.length && i < 20; i++) {
      intervals.add(
        events[i].timestamp.difference(events[i - 1].timestamp).inMilliseconds,
      );
    }

    if (intervals.length >= 3) {
      final avg = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals
          .map((i) => (i - avg) * (i - avg))
          .reduce((a, b) => a + b) / intervals.length;

      if (variance < 2500) {
        // Ecart type < 50ms — trop regulier pour un humain
        score += 0.4;
      }
    }

    // 2. Enumeration systematique
    final recentCmds = events
        .sublist(max(0, events.length - 20))
        .map((e) => e.command)
        .toList();
    final enumCmds = ['ls', 'cat', 'find', 'grep', 'head', 'tail'];
    final enumCount = recentCmds
        .where((cmd) => enumCmds.any((e) => cmd.startsWith(e)))
        .length;
    if (enumCount > recentCmds.length * 0.7) {
      score += 0.3;
    }

    // 3. Absence de patterns humains (pas de pause > 5s)
    bool hasPause = false;
    for (int i = 1; i < events.length && i < 20; i++) {
      if (events[i].timestamp.difference(events[i - 1].timestamp) >
          const Duration(seconds: 5)) {
        hasPause = true;
        break;
      }
    }
    if (!hasPause && events.length > 10) {
      score += 0.2;
    }

    return score.clamp(0.0, 1.0);
  }

  bool _isDangerousCommand(String cmd) {
    const dangerous = [
      'rm -rf', 'chmod 777', 'dd if=', 'mkfs.',
      'shutdown', 'reboot', 'cat /etc/shadow',
      'passwd', 'curl | sh', 'wget -O- | sh',
    ];
    return dangerous.any((d) => cmd.contains(d));
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Singleton :
//   final rateLimiter = AIRateLimiter();
//   final analyzer = BehavioralAnalyzer();
//
// Avant chaque action SSH :
//   final rateResult = rateLimiter.check(sessionId);
//   if (rateResult == RateLimitAction.blocked) {
//     secureLog.log(LogSeverity.alert, 'ai_detection',
//       'Rate limit depasse — possible agent IA');
//     failGuard.forceOpen('Agent IA detecte');
//     return;
//   }
//
//   final event = BehaviorEvent(
//     command: sshCommand,
//     timestamp: DateTime.now(),
//     sessionId: sessionId,
//   );
//   analyzer.recordEvent(event);
//   final anomaly = analyzer.analyzeEvent(event);
//
//   if (anomaly.action == AnomalyAction.block) {
//     secureLog.log(LogSeverity.alert, 'behavioral',
//       'Agent IA detecte: ${anomaly.anomalies.join(", ")}');
//     killSwitch.execute(reason: KillReason.aiAgentDetected, ...);
//   }
// =============================================================
