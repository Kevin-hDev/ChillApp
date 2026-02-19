// =============================================================
// FIX-049 : Defenses contre botnets SSH
// GAP-049: Defenses contre botnets SSH absentes (P2)
// FIX-050 : Monitoring Tailscale ACLs
// GAP-050: Monitoring Tailscale ACLs absent (P1)
// Cible: lib/core/security/botnet_tailscale_monitor.dart (nouveau)
// =============================================================
//
// PROBLEME GAP-049 : Les botnets SSH (SSHStalker, AyySSHush,
// PumaBot) peuvent persister sur les routeurs et equipements IoT.
//
// PROBLEME GAP-050 : Les ACLs Tailscale ne sont pas verifiees
// regulierement. Une mauvaise config peut permettre un acces
// non autorise (ref: TS-2025-006).
//
// SOLUTION :
// 1. Audit regulier de authorized_keys sur le PC cible
// 2. Detection de cles inconnues
// 3. Verification des ACLs Tailscale via l'API
// 4. Alertes sur les configurations dangereuses
// =============================================================

import 'dart:io';
import 'dart:convert';

/// Resultat d'un audit de cles autorisees.
class AuthorizedKeysAudit {
  final int totalKeys;
  final int knownKeys;
  final int unknownKeys;
  final List<String> unknownKeyFingerprints;
  final DateTime auditTimestamp;

  const AuthorizedKeysAudit({
    required this.totalKeys,
    required this.knownKeys,
    required this.unknownKeys,
    required this.unknownKeyFingerprints,
    required this.auditTimestamp,
  });

  bool get isClean => unknownKeys == 0;
}

/// Probleme detecte dans les ACLs Tailscale.
class AclIssue {
  final String severity; // critical, warning, info
  final String description;
  final String recommendation;

  const AclIssue({
    required this.severity,
    required this.description,
    required this.recommendation,
  });
}

/// Detecteur de botnets SSH et moniteur Tailscale.
class BotnetTailscaleMonitor {
  /// Cles autorisees connues (hash SHA-256 des cles publiques).
  final Set<String> _knownKeyHashes = {};

  /// Enregistre une cle connue (au deploiement).
  void registerKnownKey(String pubKeyContent) {
    // Extraire la partie cle (sans commentaire)
    final parts = pubKeyContent.trim().split(' ');
    if (parts.length >= 2) {
      _knownKeyHashes.add(parts[1]);
    }
  }

  /// Audit des cles autorisees sur la machine locale.
  Future<AuthorizedKeysAudit> auditLocalAuthorizedKeys() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '';
    final authKeysFile = File('$home/.ssh/authorized_keys');

    if (!await authKeysFile.exists()) {
      return AuthorizedKeysAudit(
        totalKeys: 0,
        knownKeys: 0,
        unknownKeys: 0,
        unknownKeyFingerprints: [],
        auditTimestamp: DateTime.now(),
      );
    }

    final content = await authKeysFile.readAsString();
    final lines = content.split('\n')
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();

    int known = 0;
    int unknown = 0;
    final unknownFingerprints = <String>[];

    for (final line in lines) {
      final parts = line.trim().split(' ');
      if (parts.length >= 2) {
        if (_knownKeyHashes.contains(parts[1])) {
          known++;
        } else {
          unknown++;
          // Calculer le fingerprint pour le log
          unknownFingerprints.add(
            '${parts[0]} ${parts[1].substring(0, 20)}...'
            '${parts.length > 2 ? " (${parts[2]})" : ""}');
        }
      }
    }

    return AuthorizedKeysAudit(
      totalKeys: lines.length,
      knownKeys: known,
      unknownKeys: unknown,
      unknownKeyFingerprints: unknownFingerprints,
      auditTimestamp: DateTime.now(),
    );
  }

  /// Audit des cles autorisees sur un hote distant.
  Future<AuthorizedKeysAudit> auditRemoteAuthorizedKeys({
    required String host,
    required String user,
    int port = 22,
  }) async {
    try {
      final result = await Process.run('ssh', [
        '-p', '$port',
        '-o', 'ConnectTimeout=10',
        '$user@$host',
        'cat ~/.ssh/authorized_keys 2>/dev/null || echo ""',
      ]);

      if (result.exitCode != 0) {
        return AuthorizedKeysAudit(
          totalKeys: -1,
          knownKeys: 0,
          unknownKeys: 0,
          unknownKeyFingerprints: [],
          auditTimestamp: DateTime.now(),
        );
      }

      final content = result.stdout.toString();
      final lines = content.split('\n')
          .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
          .toList();

      int known = 0;
      int unknown = 0;
      final unknownFingerprints = <String>[];

      for (final line in lines) {
        final parts = line.trim().split(' ');
        if (parts.length >= 2) {
          if (_knownKeyHashes.contains(parts[1])) {
            known++;
          } else {
            unknown++;
            unknownFingerprints.add(
              '${parts[0]} ${parts[1].substring(0, 20)}...');
          }
        }
      }

      return AuthorizedKeysAudit(
        totalKeys: lines.length,
        knownKeys: known,
        unknownKeys: unknown,
        unknownKeyFingerprints: unknownFingerprints,
        auditTimestamp: DateTime.now(),
      );
    } catch (_) {
      return AuthorizedKeysAudit(
        totalKeys: -1,
        knownKeys: 0,
        unknownKeys: 0,
        unknownKeyFingerprints: [],
        auditTimestamp: DateTime.now(),
      );
    }
  }

  /// Verifie les ACLs Tailscale pour les configurations dangereuses.
  Future<List<AclIssue>> auditTailscaleAcls() async {
    final issues = <AclIssue>[];

    try {
      // Verifier le statut Tailscale
      final result = await Process.run('tailscale', ['status', '--json']);
      if (result.exitCode != 0) {
        issues.add(const AclIssue(
          severity: 'critical',
          description: 'Impossible de lire le statut Tailscale',
          recommendation: 'Verifier que Tailscale est installe et demarre',
        ));
        return issues;
      }

      final status = jsonDecode(result.stdout.toString());

      // Verifier si le noeud est autorise
      if (status['Self'] != null) {
        final self = status['Self'];

        // Verifier le nombre de capabilities
        if (self['Capabilities'] != null) {
          final caps = self['Capabilities'] as List;
          if (caps.contains('*')) {
            issues.add(const AclIssue(
              severity: 'critical',
              description: 'ACL wildcard (*) detectee — acces illimite',
              recommendation: 'Restreindre les ACLs a des regles specifiques '
                  'par tag ou par utilisateur',
            ));
          }
        }

        // Verifier si SSH est active
        if (self['SSHHostKeys'] == null) {
          issues.add(const AclIssue(
            severity: 'warning',
            description: 'Tailscale SSH non active',
            recommendation: 'Activer Tailscale SSH pour l\'audit integre '
                '(tailscale up --ssh)',
          ));
        }
      }

      // Verifier les pairs connectes
      if (status['Peer'] != null) {
        final peers = status['Peer'] as Map<String, dynamic>;
        for (final entry in peers.entries) {
          final peer = entry.value as Map<String, dynamic>;
          // Verifier si des pairs inconnus sont connectes
          if (peer['Online'] == true && peer['ShareeNode'] == true) {
            issues.add(AclIssue(
              severity: 'warning',
              description: 'Noeud partage detecte: ${peer['HostName']}',
              recommendation: 'Verifier que ce partage est intentionnel',
            ));
          }
        }
      }
    } catch (e) {
      issues.add(AclIssue(
        severity: 'warning',
        description: 'Erreur audit Tailscale: $e',
        recommendation: 'Verifier la configuration Tailscale',
      ));
    }

    return issues;
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Au demarrage et periodiquement :
//   final monitor = BotnetTailscaleMonitor();
//
//   // Enregistrer les cles connues
//   monitor.registerKnownKey(await File('~/.ssh/id_ed25519.pub').readAsString());
//
//   // Audit local
//   final localAudit = await monitor.auditLocalAuthorizedKeys();
//   if (!localAudit.isClean) {
//     secureLog.log(LogSeverity.alert, 'botnet',
//       '${localAudit.unknownKeys} cles inconnues dans authorized_keys');
//   }
//
//   // Audit Tailscale ACLs
//   final aclIssues = await monitor.auditTailscaleAcls();
//   for (final issue in aclIssues.where((i) => i.severity == 'critical')) {
//     secureLog.log(LogSeverity.critical, 'tailscale_acl', issue.description);
//   }
// =============================================================
