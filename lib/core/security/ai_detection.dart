// FIX-052/053 — Détection d'agents IA + Analyse comportementale
// Rate limiting adaptatif et analyse des patterns comportementaux
// pour détecter les accès automatisés (agents IA, scripts malveillants).
import 'dart:collection';
import 'dart:math';

/// Action retournée par le rate limiter.
enum RateLimitAction {
  allowed,
  slowdown,
  blocked,
}

/// Rate limiter adaptatif par identifiant.
///
/// Suivi d'une fenêtre glissante de requêtes par identifiant.
/// Au-delà du seuil de ralentissement, des délais exponentiels sont appliqués.
/// Au-delà du seuil de blocage, toute requête est rejetée.
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

  /// Nombre maximal d'identifiants distincts suivis.
  /// Au-delà, un cleanup forcé est déclenché pour éviter la croissance mémoire.
  static const int maxIdentifiers = 10000;

  /// Vérifie si l'identifiant est autorisé à effectuer une action.
  RateLimitAction check(String identifier) {
    final now = DateTime.now();

    // Protection contre la croissance mémoire non bornée
    if (_history.length > maxIdentifiers) {
      cleanup();
    }

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

  /// Retourne le délai de ralentissement proportionnel à l'excès de requêtes.
  Duration getSlowdownDelay(String identifier) {
    final history = _history[identifier];
    if (history == null) return Duration.zero;
    final excess = history.length - slowdownThreshold;
    if (excess <= 0) return Duration.zero;
    return Duration(milliseconds: excess * 200);
  }

  /// Nettoie les entrées expirées pour libérer la mémoire.
  void cleanup() {
    final now = DateTime.now();
    _history.forEach((key, history) {
      history.removeWhere((t) => now.difference(t) > window);
    });
    _history.removeWhere((_, history) => history.isEmpty);
  }

  /// Retourne le nombre de requêtes actives pour un identifiant (pour les tests).
  int getCount(String identifier) {
    return _history[identifier]?.length ?? 0;
  }
}

/// Événement comportemental enregistré dans l'historique.
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

/// Résultat de l'analyse d'anomalie.
class AnomalyResult {
  /// Score de 0.0 (normal) à 1.0 (très suspect).
  final double score;
  final List<String> anomalies;
  final AnomalyAction action;

  const AnomalyResult({
    required this.score,
    required this.anomalies,
    required this.action,
  });
}

/// Action recommandée après analyse d'anomalie.
enum AnomalyAction {
  allow,
  warn,
  block,
}

/// Analyseur comportemental pour détecter les agents IA.
///
/// Maintient un historique glissant d'événements (max 1000) et détecte :
/// - Horaires inhabituels
/// - Commandes inconnues
/// - Commandes dangereuses
/// - Rafales de commandes (burst)
/// - Patterns caractéristiques des agents IA (régularité, énumération systématique)
class BehavioralAnalyzer {
  final Queue<BehaviorEvent> _history = Queue();
  final Map<String, int> _commandFrequency = {};
  final Map<int, int> _hourDistribution = {};
  static const int maxHistory = 1000;

  /// Nombre d'événements dans l'historique (pour les tests).
  int get historyLength => _history.length;

  /// Enregistre un événement comportemental.
  void recordEvent(BehaviorEvent event) {
    _history.addLast(event);
    if (_history.length > maxHistory) _history.removeFirst();

    _commandFrequency[event.command] =
        (_commandFrequency[event.command] ?? 0) + 1;
    _hourDistribution[event.timestamp.hour] =
        (_hourDistribution[event.timestamp.hour] ?? 0) + 1;
  }

  /// Analyse un événement et retourne un score d'anomalie.
  AnomalyResult analyzeEvent(BehaviorEvent event) {
    final anomalies = <String>[];
    double score = 0.0;
    final totalEvents = _history.length;

    // 1. Horaire inhabituel (< 2 % des événements historiques sur cette heure)
    if (totalEvents > 50) {
      final hourCount = _hourDistribution[event.timestamp.hour] ?? 0;
      if (hourCount < totalEvents * 0.02) {
        anomalies.add('Horaire inhabituel (${event.timestamp.hour}h)');
        score += 0.2;
      }
    }

    // 2. Commande jamais vue dans l'historique
    if (!_commandFrequency.containsKey(event.command) && totalEvents > 50) {
      anomalies.add('Commande inconnue: ${event.command}');
      score += 0.3;
    }

    // 3. Commande dangereuse (score fort immédiat)
    if (isDangerousCommand(event.command)) {
      anomalies.add('Commande dangereuse');
      score += 0.5;
    }

    // 4. Rafale : plus de 10 commandes dans la dernière minute
    final recentCount = _history
        .where((e) => e.timestamp
            .isAfter(DateTime.now().subtract(const Duration(minutes: 1))))
        .length;
    if (recentCount > 10) {
      anomalies.add('Rafale: $recentCount commandes/min');
      score += 0.3;
    }

    // 5. Patterns d'agents IA (timing régulier, énumération, absence de pauses)
    final aiScore = detectAIPatterns();
    if (aiScore > 0) {
      anomalies.add(
          'Pattern agent IA detecte (score: ${aiScore.toStringAsFixed(2)})');
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

  /// Détecte les patterns caractéristiques des agents IA.
  ///
  /// Trois indicateurs combinés :
  /// 1. Timing trop régulier (variance < 2 500 ms²)
  /// 2. Énumération systématique (> 70 % de commandes de type ls/cat/find/grep)
  /// 3. Absence de pauses humaines (aucun délai > 5 s sur 20 événements)
  ///
  /// Public pour les tests.
  double detectAIPatterns() {
    if (_history.length < 5) return 0.0;

    double score = 0.0;
    final events = _history.toList();

    // 1. Timing trop régulier (un humain varie naturellement)
    final intervals = <int>[];
    for (int i = 1; i < events.length && i < 20; i++) {
      intervals.add(
        events[i]
            .timestamp
            .difference(events[i - 1].timestamp)
            .inMilliseconds,
      );
    }

    if (intervals.length >= 3) {
      final avg = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals
              .map((i) => (i - avg) * (i - avg))
              .reduce((a, b) => a + b) /
          intervals.length;

      if (variance < 2500) {
        score += 0.4;
      }
    }

    // 2. Énumération systématique (pattern de reconnaissance automatisée)
    final recentCmds = events
        .sublist(max(0, events.length - 20))
        .map((e) => e.command)
        .toList();
    final enumCmds = ['ls', 'cat', 'find', 'grep', 'head', 'tail'];
    final enumCount =
        recentCmds.where((cmd) => enumCmds.any((e) => cmd.startsWith(e))).length;
    if (recentCmds.isNotEmpty && enumCount > recentCmds.length * 0.7) {
      score += 0.3;
    }

    // 3. Absence de pauses humaines (un humain s'arrête naturellement)
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

  /// Vérifie si une commande est considérée comme dangereuse.
  ///
  /// Public pour les tests. Méthode statique pour pouvoir être utilisée
  /// sans instancier l'analyseur.
  static bool isDangerousCommand(String cmd) {
    const dangerous = [
      'rm -rf',
      'chmod 777',
      'dd if=',
      'mkfs.',
      'shutdown',
      'reboot',
      'cat /etc/shadow',
      'passwd',
      'curl | sh',
      'wget -O- | sh',
    ];
    return dangerous.any((d) => cmd.contains(d));
  }
}
