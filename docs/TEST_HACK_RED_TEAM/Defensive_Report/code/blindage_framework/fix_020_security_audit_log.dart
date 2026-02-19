// =============================================================
// FIX-020 : Journalisation securisee des actions securite
// GAP-020: Journalisation des actions securite absente
// Cible: lib/core/security/security_audit_log.dart (nouveau)
// =============================================================
//
// PROBLEME : Quand quelqu'un desactive le pare-feu, AppArmor ou
// fail2ban via l'app, il n'y a aucune trace de cette action.
// Impossible de retracer une compromission.
//
// SOLUTION :
// 1. Journal d'audit local horodate
// 2. Chaque entree signee (HMAC) pour anti-tamper
// 3. Chaine de hachage (comme une blockchain simplifiee)
// 4. Ne JAMAIS logger de secrets (PIN, cles, tokens)
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'dart:math';

/// Types d'actions de securite journalisees.
enum SecurityAction {
  firewallEnabled,
  firewallDisabled,
  appArmorEnabled,
  appArmorDisabled,
  fail2banEnabled,
  fail2banDisabled,
  sshRootLoginDisabled,
  sshRootLoginEnabled,
  pinSet,
  pinChanged,
  pinVerifyFailed,
  pinVerifySuccess,
  lockEnabled,
  lockDisabled,
  daemonStarted,
  daemonStopped,
  daemonIntegrityFail,
  tailscaleConnected,
  tailscaleDisconnected,
  screenshotDetected,
  debuggerDetected,
  fridaDetected,
  libraryInjectionDetected,
  captureProcessDetected,
  killSwitchActivated,
}

/// Entree dans le journal d'audit.
class AuditEntry {
  final DateTime timestamp;
  final SecurityAction action;
  final String detail;
  final String previousHash;
  final String entryHash;

  AuditEntry({
    required this.timestamp,
    required this.action,
    required this.detail,
    required this.previousHash,
    required this.entryHash,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toUtc().toIso8601String(),
    'action': action.name,
    'detail': detail,
    'prev': previousHash,
    'hash': entryHash,
  };

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      timestamp: DateTime.parse(json['ts'] as String),
      action: SecurityAction.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => SecurityAction.firewallEnabled,
      ),
      detail: json['detail'] as String,
      previousHash: json['prev'] as String,
      entryHash: json['hash'] as String,
    );
  }
}

/// Journal d'audit securise avec chaine de hachage.
class SecurityAuditLog {
  final File _logFile;
  final Uint8List _hmacKey;
  String _lastHash;
  static const int _maxEntries = 10000;

  SecurityAuditLog._({
    required File logFile,
    required Uint8List hmacKey,
    required String lastHash,
  })  : _logFile = logFile,
        _hmacKey = hmacKey,
        _lastHash = lastHash;

  /// Cree ou ouvre le journal d'audit.
  /// Le hmacKey doit etre stocke separement (secure storage).
  static Future<SecurityAuditLog> open({
    required String logPath,
    required Uint8List hmacKey,
  }) async {
    final logFile = File(logPath);
    String lastHash = '0' * 64; // Genesis hash

    if (await logFile.exists()) {
      // Lire la derniere ligne pour obtenir le dernier hash
      final lines = await logFile.readAsLines();
      if (lines.isNotEmpty) {
        try {
          final lastEntry = jsonDecode(lines.last) as Map<String, dynamic>;
          lastHash = lastEntry['hash'] as String? ?? lastHash;
        } catch (_) {
          // Journal corrompu, on continue avec le genesis
        }
      }
    } else {
      // Creer le fichier avec les permissions restrictives
      await logFile.create(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', logPath]);
      }
    }

    return SecurityAuditLog._(
      logFile: logFile,
      hmacKey: hmacKey,
      lastHash: lastHash,
    );
  }

  /// Enregistre une action dans le journal.
  /// [detail] ne doit JAMAIS contenir de secrets.
  Future<void> log(SecurityAction action, {String detail = ''}) async {
    // Sanitiser le detail (supprimer tout ce qui ressemble a un secret)
    final safeDetail = _sanitize(detail);

    final timestamp = DateTime.now().toUtc();

    // Construire le contenu a signer
    final content = '${timestamp.toIso8601String()}'
        '|${action.name}'
        '|$safeDetail'
        '|$_lastHash';

    // Calculer le HMAC-SHA256
    final hmac = Hmac(sha256, _hmacKey);
    final entryHash = hmac.convert(utf8.encode(content)).toString();

    final entry = AuditEntry(
      timestamp: timestamp,
      action: action,
      detail: safeDetail,
      previousHash: _lastHash,
      entryHash: entryHash,
    );

    // Ecrire dans le fichier (append)
    await _logFile.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
    );

    _lastHash = entryHash;

    // Rotation si necessaire
    await _rotateIfNeeded();
  }

  /// Verifie l'integrite de la chaine de hachage.
  /// Retourne la liste des entrees invalides (indices).
  Future<List<int>> verifyIntegrity() async {
    final corrupted = <int>[];

    if (!await _logFile.exists()) return corrupted;

    final lines = await _logFile.readAsLines();
    String previousHash = '0' * 64;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;

      try {
        final json = jsonDecode(lines[i]) as Map<String, dynamic>;
        final entry = AuditEntry.fromJson(json);

        // Verifier la chaine
        if (entry.previousHash != previousHash) {
          corrupted.add(i);
        }

        // Verifier le HMAC
        final content = '${entry.timestamp.toUtc().toIso8601String()}'
            '|${entry.action.name}'
            '|${entry.detail}'
            '|${entry.previousHash}';

        final hmac = Hmac(sha256, _hmacKey);
        final expectedHash = hmac.convert(utf8.encode(content)).toString();

        if (entry.entryHash != expectedHash) {
          corrupted.add(i);
        }

        previousHash = entry.entryHash;
      } catch (_) {
        corrupted.add(i);
      }
    }

    return corrupted;
  }

  /// Lit les N dernieres entrees.
  Future<List<AuditEntry>> readLast(int count) async {
    if (!await _logFile.exists()) return [];

    final lines = await _logFile.readAsLines();
    final start = lines.length > count ? lines.length - count : 0;

    return lines
        .sublist(start)
        .where((l) => l.trim().isNotEmpty)
        .map((l) {
          try {
            return AuditEntry.fromJson(
                jsonDecode(l) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .where((e) => e != null)
        .cast<AuditEntry>()
        .toList();
  }

  /// Genere une cle HMAC aleatoire pour le journal.
  static Uint8List generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
  }

  /// Sanitise le detail pour eviter de logger des secrets.
  static String _sanitize(String input) {
    var safe = input;

    // Supprimer les chemins absolus
    safe = safe.replaceAll(
      RegExp(r'(/home/[^\s]+|/Users/[^\s]+|C:\\Users\\[^\s]+)'),
      '[PATH]',
    );

    // Supprimer les adresses IP (sauf Tailscale 100.x.x.x)
    safe = safe.replaceAll(
      RegExp(r'\b(?!100\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      '[IP]',
    );

    // Supprimer ce qui ressemble a un token/cle
    safe = safe.replaceAll(
      RegExp(r'[A-Za-z0-9+/=]{32,}'),
      '[REDACTED]',
    );

    // Limiter la longueur
    if (safe.length > 200) safe = '${safe.substring(0, 200)}...';

    return safe;
  }

  /// Rotation : archiver et commencer un nouveau fichier.
  Future<void> _rotateIfNeeded() async {
    final lines = await _logFile.readAsLines();
    if (lines.length <= _maxEntries) return;

    // Archiver
    final archivePath = '${_logFile.path}.${DateTime.now().millisecondsSinceEpoch}';
    await _logFile.copy(archivePath);

    // Garder les 1000 dernieres lignes
    final keep = lines.sublist(lines.length - 1000);
    await _logFile.writeAsString('${keep.join('\n')}\n');
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Creer lib/core/security/security_audit_log.dart
//
// 2. Initialiser dans main.dart :
//    final auditKey = SecurityAuditLog.generateKey();
//    // Stocker auditKey dans secure storage (voir P5)
//    final auditLog = await SecurityAuditLog.open(
//      logPath: '${appDir}/security_audit.log',
//      hmacKey: auditKey,
//    );
//
// 3. Dans security_commands.dart, logger chaque action :
//    await auditLog.log(SecurityAction.firewallDisabled,
//      detail: 'Desactive par l\'utilisateur');
//
// 4. Verification periodique :
//    final corrupted = await auditLog.verifyIntegrity();
//    if (corrupted.isNotEmpty) {
//      // ALERTE : journal d'audit altere !
//    }
// =============================================================
