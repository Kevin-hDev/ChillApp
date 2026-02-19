// =============================================================
// FIX-057 : Preparation forensique
// GAP-057: Preparation forensique absente (P3)
// FIX-058 : Preparation reglementaire CRA
// GAP-058: Preparation reglementaire CRA absente (P3)
// Cible: lib/core/security/forensics_compliance.dart (nouveau)
// =============================================================
//
// PROBLEME GAP-057 : En cas de compromission suspectee, aucun
// moyen de collecter des preuves (anomalies binaires, URLs
// injectees, flux reseau inhabituels).
//
// PROBLEME GAP-058 : Le Cyber Resilience Act (CRA) entre en
// vigueur en septembre 2026. Reporting obligatoire des
// vulnerabilites. ChillApp doit se preparer.
//
// SOLUTION :
// 1. Collecte forensique automatisee en cas d'alerte
// 2. Verification d'integrite des binaires
// 3. Rapport forensique exportable
// 4. Templates CRA pour le reporting de vulnerabilites
// =============================================================

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Type de preuve forensique.
enum ForensicEvidenceType {
  binaryIntegrity,
  networkAnomaly,
  fileAnomaly,
  processAnomaly,
  logAnomaly,
}

/// Preuve forensique collectee.
class ForensicEvidence {
  final ForensicEvidenceType type;
  final DateTime collectedAt;
  final String description;
  final Map<String, dynamic> data;

  const ForensicEvidence({
    required this.type,
    required this.collectedAt,
    required this.description,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'collected_at': collectedAt.toIso8601String(),
    'description': description,
    'data': data,
  };
}

/// Collecteur de preuves forensiques.
class ForensicsCollector {
  final List<ForensicEvidence> _evidence = [];

  /// Collecte toutes les preuves disponibles.
  Future<List<ForensicEvidence>> collectAll() async {
    _evidence.clear();

    await _checkBinaryIntegrity();
    await _checkRunningProcesses();
    await _checkNetworkConnections();
    await _checkFileAnomalies();

    return List.unmodifiable(_evidence);
  }

  /// Verifie l'integrite des binaires de l'app.
  Future<void> _checkBinaryIntegrity() async {
    try {
      final execPath = Platform.resolvedExecutable;
      final file = File(execPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();

        _evidence.add(ForensicEvidence(
          type: ForensicEvidenceType.binaryIntegrity,
          collectedAt: DateTime.now(),
          description: 'Hash SHA-256 du binaire principal',
          data: {
            'path': execPath,
            'sha256': hash,
            'size': bytes.length,
          },
        ));
      }
    } catch (_) {}
  }

  /// Liste les processus en cours d'execution.
  Future<void> _checkRunningProcesses() async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('powershell', [
          '-Command', 'Get-Process | Select-Object Name,Id,Path | ConvertTo-Json',
        ]);
      } else {
        result = await Process.run('ps', ['aux']);
      }

      if (result.exitCode == 0) {
        final output = result.stdout.toString();

        // Chercher des processus suspects
        final suspicious = <String>[];
        final suspiciousNames = [
          'frida', 'gdb', 'lldb', 'strace', 'ltrace',
          'mitmproxy', 'burp', 'charles', 'wireshark',
          'tcpdump', 'nmap', 'metasploit', 'hydra',
        ];

        for (final name in suspiciousNames) {
          if (output.toLowerCase().contains(name)) {
            suspicious.add(name);
          }
        }

        _evidence.add(ForensicEvidence(
          type: ForensicEvidenceType.processAnomaly,
          collectedAt: DateTime.now(),
          description: 'Analyse des processus',
          data: {
            'suspicious_found': suspicious,
            'total_output_size': output.length,
          },
        ));
      }
    } catch (_) {}
  }

  /// Verifie les connexions reseau actives.
  Future<void> _checkNetworkConnections() async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('netstat', ['-ano']);
      } else {
        result = await Process.run('ss', ['-tunap']);
      }

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');

        // Chercher des connexions non-Tailscale
        final nonTailscale = lines.where((l) {
          // Ignorer les lignes d'en-tete et localhost
          if (l.contains('127.0.0.1') || l.contains('::1')) return false;
          if (l.contains('100.64.') || l.contains('100.') &&
              !l.contains('100.63')) return false;
          return l.contains('ESTABLISHED') || l.contains('ESTAB');
        }).toList();

        if (nonTailscale.isNotEmpty) {
          _evidence.add(ForensicEvidence(
            type: ForensicEvidenceType.networkAnomaly,
            collectedAt: DateTime.now(),
            description: 'Connexions non-Tailscale detectees',
            data: {
              'connections': nonTailscale.take(20).toList(),
              'count': nonTailscale.length,
            },
          ));
        }
      }
    } catch (_) {}
  }

  /// Verifie les anomalies de fichiers.
  Future<void> _checkFileAnomalies() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '';

    // Verifier les fichiers recemment modifies dans .ssh
    try {
      final sshDir = Directory('$home/.ssh');
      if (await sshDir.exists()) {
        final recentlyModified = <Map<String, dynamic>>[];
        final cutoff = DateTime.now().subtract(const Duration(hours: 1));

        await for (final entity in sshDir.list()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (stat.modified.isAfter(cutoff)) {
              recentlyModified.add({
                'path': entity.path,
                'modified': stat.modified.toIso8601String(),
                'size': stat.size,
              });
            }
          }
        }

        if (recentlyModified.isNotEmpty) {
          _evidence.add(ForensicEvidence(
            type: ForensicEvidenceType.fileAnomaly,
            collectedAt: DateTime.now(),
            description: 'Fichiers SSH modifies recemment',
            data: {'files': recentlyModified},
          ));
        }
      }
    } catch (_) {}
  }

  /// Genere un rapport forensique complet.
  String generateReport() {
    return const JsonEncoder.withIndent('  ').convert({
      'forensic_report': {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'platform': Platform.operatingSystem,
        'platform_version': Platform.operatingSystemVersion,
        'dart_version': Platform.version,
        'evidence_count': _evidence.length,
        'evidence': _evidence.map((e) => e.toJson()).toList(),
      },
    });
  }
}

/// Templates de conformite CRA (Cyber Resilience Act).
class CraCompliance {
  /// Template de notification de vulnerabilite.
  /// Requis par le CRA a partir de septembre 2026.
  static Map<String, dynamic> vulnerabilityNotificationTemplate({
    required String productName,
    required String vulnerabilityId,
    required String description,
    required String severity,
    required String status,
  }) {
    return {
      'notification_type': 'actively_exploited_vulnerability',
      'product': {
        'name': productName,
        'version': 'voir pubspec.yaml',
        'category': 'desktop_application',
      },
      'vulnerability': {
        'id': vulnerabilityId,
        'description': description,
        'severity': severity,
        'cvss_score': null,
        'cwe_id': null,
      },
      'timeline': {
        'discovered_at': null,
        'reported_at': DateTime.now().toUtc().toIso8601String(),
        'fixed_at': null,
      },
      'status': status,
      'contact': {
        'manufacturer': 'ChillApp Team',
        'email': null,
      },
      'cra_reference': 'EU Regulation 2024/2847, Article 14',
      'notification_deadline': '24 hours from discovery '
          '(actively exploited) or 72 hours (non-exploited)',
    };
  }

  /// Checklist de conformite CRA.
  static List<Map<String, dynamic>> complianceChecklist() {
    return [
      {
        'requirement': 'Vulnerability handling',
        'article': 'Article 13',
        'status': 'implemented',
        'details': 'SecureLogger + ForensicsCollector',
      },
      {
        'requirement': 'Incident notification (24h)',
        'article': 'Article 14(1)',
        'status': 'template_ready',
        'details': 'vulnerabilityNotificationTemplate()',
      },
      {
        'requirement': 'Security updates',
        'article': 'Article 13(8)',
        'status': 'implemented',
        'details': 'Rotation cles SSH, mise a jour automatique',
      },
      {
        'requirement': 'Secure by default',
        'article': 'Article 13(1)',
        'status': 'implemented',
        'details': 'Fail closed, algorithmes durcis, pas de fallback',
      },
      {
        'requirement': 'Documentation technique',
        'article': 'Article 31',
        'status': 'in_progress',
        'details': 'Rapport defensif (P8)',
      },
    ];
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Collecte forensique en cas d'alerte :
//   final forensics = ForensicsCollector();
//   final evidence = await forensics.collectAll();
//   final report = forensics.generateReport();
//   // Sauvegarder le rapport
//   await File('forensic_report.json').writeAsString(report);
//
// 2. Conformite CRA :
//   final checklist = CraCompliance.complianceChecklist();
//   // Afficher dans l'ecran securite
//
// 3. Notification de vulnerabilite :
//   final notification = CraCompliance.vulnerabilityNotificationTemplate(
//     productName: 'ChillApp',
//     vulnerabilityId: 'CVE-XXXX-XXXX',
//     description: '...',
//     severity: 'HIGH',
//     status: 'investigating',
//   );
// =============================================================
