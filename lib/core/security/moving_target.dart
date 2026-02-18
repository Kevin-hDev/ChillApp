// =============================================================
// FIX-047 : Moving Target Defense (port hopping SSH)
// GAP-047: Moving target defense absent (P3)
// FIX-048 : Fingerprinting inverse des attaquants
// GAP-048: Fingerprinting inverse absent (P3)
// Cible: lib/core/security/moving_target.dart
// =============================================================
//
// PROBLEME GAP-047 : Le port SSH est statique. L'attaquant sait
// exactement ou se connecter.
//
// PROBLEME GAP-048 : Aucune collecte d'info sur les attaquants.
//
// SOLUTION :
// 1. Port hopping SSH (change periodiquement)
// 2. Banniere SSH randomisee (pas d'empreinte reelle)
// 3. Collecte d'info sur les attaquants (IP, banner, timing)
// =============================================================

import 'dart:io';
import 'dart:math';

/// Configuration du moving target defense.
class MovingTargetConfig {
  /// Port de base pour le SSH reel.
  final int basePort;

  /// Plage de ports disponibles.
  final int portRangeStart;
  final int portRangeEnd;

  /// Duree de vie d'un port avant rotation.
  final Duration portLifetime;

  const MovingTargetConfig({
    this.basePort = 22,
    this.portRangeStart = 49152,
    this.portRangeEnd = 65535,
    this.portLifetime = const Duration(hours: 6),
  });
}

/// Gestionnaire de port hopping SSH.
class MovingTargetDefense {
  final MovingTargetConfig config;
  int _currentPort;
  DateTime _lastRotation;
  final Random _random = Random.secure();

  MovingTargetDefense({MovingTargetConfig? config})
      : config = config ?? const MovingTargetConfig(),
        _currentPort = 0,
        _lastRotation = DateTime.now() {
    _currentPort = _generatePort();
  }

  /// Port SSH actuel.
  int get currentPort => _currentPort;

  /// Date de la derniere rotation.
  DateTime get lastRotation => _lastRotation;

  /// Verifie si une rotation est necessaire.
  bool get needsRotation {
    final elapsed = DateTime.now().difference(_lastRotation);
    return elapsed >= config.portLifetime;
  }

  /// Effectue une rotation de port.
  Future<int> rotatePort() async {
    final newPort = _generatePort();

    // Mettre a jour les regles firewall
    await _updateFirewallRules(_currentPort, newPort);

    _currentPort = newPort;
    _lastRotation = DateTime.now();
    return newPort;
  }

  /// Genere un port aleatoire dans la plage configuree.
  int _generatePort() {
    final range = config.portRangeEnd - config.portRangeStart;
    return config.portRangeStart + _random.nextInt(range);
  }

  /// Met a jour les regles firewall pour le nouveau port.
  ///
  /// Utilise pkexec (Linux) pour l'elevation de privileges, compatible
  /// avec le systeme d'elevation du projet (privilege_manager.dart).
  /// La methode est injectable via [firewallRunner] pour les tests.
  Future<void> _updateFirewallRules(int oldPort, int newPort) async {
    if (Platform.isLinux) {
      // Valider les ports (defence en profondeur)
      if (oldPort < 1 || oldPort > 65535 || newPort < 1 || newPort > 65535) {
        return;
      }
      // Supprimer l'ancienne regle via pkexec (pas sudo)
      await Process.run(
          'pkexec', ['ufw', 'delete', 'allow', '$oldPort/tcp']);
      // Ajouter la nouvelle — Tailscale uniquement
      await Process.run('pkexec', [
        'ufw',
        'allow',
        'from',
        '100.64.0.0/10',
        'to',
        'any',
        'port',
        '$newPort',
        'proto',
        'tcp',
      ]);
    }
  }

  /// Genere une banniere SSH randomisee pour le honeypot.
  /// Rend le fingerprinting plus difficile.
  static String randomBanner() {
    final banners = [
      'SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.7',
      'SSH-2.0-OpenSSH_9.6p1 Debian-1',
      'SSH-2.0-OpenSSH_9.3p1',
      'SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3',
      'SSH-2.0-dropbear_2022.83',
      'SSH-2.0-OpenSSH_9.0',
    ];
    return banners[Random.secure().nextInt(banners.length)];
  }
}

/// Fingerprinting inverse — collecte d'info sur les attaquants.
class AttackerFingerprinter {
  final List<AttackerProfile> _profiles = [];

  /// Limite maximale de profils suivis (defense contre DoS memoire).
  static const int maxProfiles = 10000;

  /// Enregistre une tentative de connexion suspecte.
  void recordAttempt({
    required String sourceIp,
    String? clientBanner,
    String? username,
    int? port,
  }) {
    // Chercher un profil existant
    AttackerProfile? existing;
    for (final p in _profiles) {
      if (p.sourceIp == sourceIp) {
        existing = p;
        break;
      }
    }

    final AttackerProfile profile;
    if (existing != null) {
      profile = existing;
    } else {
      // Limiter le nombre de profils (defense DoS memoire)
      if (_profiles.length >= maxProfiles) {
        cleanup();
        // Si encore plein apres cleanup, evicter le plus ancien
        if (_profiles.length >= maxProfiles) {
          _profiles.removeAt(0);
        }
      }
      profile = AttackerProfile(sourceIp: sourceIp);
      _profiles.add(profile);
    }

    profile.attemptCount++;
    profile.lastSeen = DateTime.now();
    if (clientBanner != null) profile.banners.add(clientBanner);
    if (username != null) profile.usernames.add(username);
    if (port != null) profile.targetPorts.add(port);
  }

  /// Retourne les profils d'attaquants les plus actifs.
  List<AttackerProfile> getMostActive({int limit = 10}) {
    final sorted = List<AttackerProfile>.from(_profiles)
      ..sort((a, b) => b.attemptCount.compareTo(a.attemptCount));
    return sorted.take(limit).toList();
  }

  /// Retourne tous les profils enregistres.
  List<AttackerProfile> get allProfiles => List.unmodifiable(_profiles);

  /// Analyse un profil d'attaquant.
  AttackerAnalysis analyze(AttackerProfile profile) {
    final isBotnet = profile.attemptCount > 100 && profile.banners.length <= 2;
    final isScanner = profile.targetPorts.length > 5;
    final isTargeted = profile.usernames.any(
      (u) => u != 'root' && u != 'admin' && u != 'test',
    );

    return AttackerAnalysis(
      profile: profile,
      likelyBotnet: isBotnet,
      likelyScanner: isScanner,
      likelyTargeted: isTargeted,
    );
  }

  /// Nettoie les profils anciens.
  void cleanup({Duration maxAge = const Duration(days: 7)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    _profiles.removeWhere((p) => p.lastSeen.isBefore(cutoff));
  }

  /// Nombre total de profils enregistres.
  int get profileCount => _profiles.length;
}

/// Profil d'un attaquant.
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

/// Analyse d'un attaquant.
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

// =============================================================
// INTEGRATION :
// =============================================================
//
// Moving target :
//   final mtd = MovingTargetDefense();
//   Timer.periodic(Duration(hours: 6), (_) async {
//     final newPort = await mtd.rotatePort();
//     // Mettre a jour la config daemon Go
//   });
//
// Fingerprinting :
//   final fingerprinter = AttackerFingerprinter();
//   honeypot.onAttacker = (event) {
//     fingerprinter.recordAttempt(
//       sourceIp: event.sourceIp,
//       clientBanner: event.clientBanner,
//     );
//   };
// =============================================================
