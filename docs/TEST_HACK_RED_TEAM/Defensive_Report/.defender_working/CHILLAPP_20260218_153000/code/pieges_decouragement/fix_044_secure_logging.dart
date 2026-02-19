// =============================================================
// FIX-044 : Secure Logging Anti-Tamper
// GAP-044: Secure logging anti-tamper absent (P1)
// Cible: lib/core/security/secure_logger.dart (nouveau)
// =============================================================
//
// NOTE : Ce fix est une extension de FIX-020 (SecurityAuditLog)
// avec un focus sur l'anti-tampering et la forensique.
//
// PROBLEME : Aucun journal securise. Les actions ne sont pas
// tracees. Impossible de retracer une intrusion.
//
// SOLUTION :
// 1. Chaine de hachage SHA-256 (blockchain-like)
// 2. Sanitisation automatique (jamais de secrets dans les logs)
// 3. Rotation et export forensique
// 4. Verification d'integrite a la demande
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Niveau de severite du log.
enum LogSeverity {
  info,
  warning,
  critical,
  alert,
}

/// Entree de log securisee avec chaine de hachage.
class SecureLogEntry {
  final int index;
  final String timestamp;
  final LogSeverity severity;
  final String category;
  final String message;
  final Map<String, dynamic>? metadata;
  final String previousHash;
  late final String hash;

  SecureLogEntry({
    required this.index,
    required this.timestamp,
    required this.severity,
    required this.category,
    required this.message,
    this.metadata,
    required this.previousHash,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'timestamp': timestamp,
    'severity': severity.name,
    'category': category,
    'message': message,
    'metadata': metadata,
    'previous_hash': previousHash,
    'hash': hash,
  };

  factory SecureLogEntry.fromJson(Map<String, dynamic> json) {
    final entry = SecureLogEntry(
      index: json['index'] as int,
      timestamp: json['timestamp'] as String,
      severity: LogSeverity.values.firstWhere((s) => s.name == json['severity']),
      category: json['category'] as String,
      message: json['message'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      previousHash: json['previous_hash'] as String,
    );
    entry.hash = json['hash'] as String;
    return entry;
  }
}

/// Logger securise avec chaine de hachage anti-tamper.
class SecureLogger {
  final String _logPath;
  final int _maxEntries;
  String _previousHash = '0' * 64;
  int _index = 0;
  final List<SecureLogEntry> _buffer = [];
  static const int _flushThreshold = 10;

  SecureLogger({
    required String logPath,
    int maxEntries = 50000,
  }) : _logPath = logPath,
       _maxEntries = maxEntries;

  /// Initialise le logger (charge l'etat precedent).
  Future<void> init() async {
    final file = File(_logPath);
    if (await file.exists()) {
      try {
        final lines = await file.readAsLines();
        if (lines.isNotEmpty) {
          final lastEntry = SecureLogEntry.fromJson(
            jsonDecode(lines.last) as Map<String, dynamic>,
          );
          _previousHash = lastEntry.hash;
          _index = lastEntry.index + 1;
        }
      } catch (_) {
        // Fichier corrompu — recommencer
        _previousHash = '0' * 64;
        _index = 0;
      }
    }
  }

  /// Ajoute une entree de log.
  Future<void> log(
    LogSeverity severity,
    String category,
    String message, {
    Map<String, dynamic>? metadata,
  }) async {
    final sanitizedMessage = _sanitize(message);
    final sanitizedMeta = metadata != null
        ? _sanitizeMap(metadata)
        : null;

    final entry = SecureLogEntry(
      index: _index,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      severity: severity,
      category: category,
      message: sanitizedMessage,
      metadata: sanitizedMeta,
      previousHash: _previousHash,
    );

    // Calculer le hash
    entry.hash = _computeHash(entry);
    _previousHash = entry.hash;
    _index++;

    _buffer.add(entry);

    // Flush si le buffer est plein
    if (_buffer.length >= _flushThreshold) {
      await flush();
    }
  }

  /// Ecrit le buffer sur disque.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    final file = File(_logPath);
    await file.parent.create(recursive: true);

    final lines = _buffer.map((e) => jsonEncode(e.toJson())).join('\n');
    await file.writeAsString('$lines\n', mode: FileMode.append);

    // Permissions restrictives
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', _logPath]);
    }

    _buffer.clear();

    // Rotation si necessaire
    await _rotateIfNeeded();
  }

  /// Verifie l'integrite de toute la chaine de logs.
  Future<bool> verifyIntegrity() async {
    final file = File(_logPath);
    if (!await file.exists()) return true;

    final lines = await file.readAsLines();
    String prevHash = '0' * 64;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = SecureLogEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );

        if (entry.previousHash != prevHash) return false;
        final computed = _computeHash(entry);
        if (computed != entry.hash) return false;

        prevHash = entry.hash;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Exporte les logs pour analyse forensique.
  Future<String> exportForForensics() async {
    await flush();
    final file = File(_logPath);
    if (!await file.exists()) return '[]';

    final lines = await file.readAsLines();
    final entries = lines
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l))
        .toList();

    return const JsonEncoder.withIndent('  ').convert({
      'export_timestamp': DateTime.now().toUtc().toIso8601String(),
      'total_entries': entries.length,
      'integrity_verified': await verifyIntegrity(),
      'entries': entries,
    });
  }

  String _computeHash(SecureLogEntry entry) {
    final data = '${entry.index}|${entry.timestamp}|'
        '${entry.severity.name}|${entry.category}|'
        '${entry.message}|${entry.previousHash}';
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// Sanitise un message (supprime les secrets potentiels).
  String _sanitize(String message) {
    var s = message;
    // Cles SSH
    s = s.replaceAll(
      RegExp(r'-----BEGIN.*KEY-----[\s\S]*?-----END.*KEY-----'),
      '[KEY_REDACTED]');
    // Tokens longs (> 32 chars de base64)
    s = s.replaceAll(RegExp(r'[A-Za-z0-9+/=]{40,}'), '[TOKEN_REDACTED]');
    // Mots de passe
    s = s.replaceAll(
      RegExp(r'password[=:]\S+', caseSensitive: false),
      'password=[REDACTED]');
    // Chemins sensibles
    s = s.replaceAll(RegExp(r'/home/\w+'), '/home/[USER]');
    s = s.replaceAll(RegExp(r'C:\\Users\\\w+'), 'C:\\Users\\[USER]');
    // IPs non-Tailscale
    s = s.replaceAll(
      RegExp(r'\b(?!100\.(?:6[4-9]|[7-9]\d|1[0-1]\d|12[0-7])\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      '[IP_REDACTED]');
    // Tronquer
    if (s.length > 500) s = '${s.substring(0, 500)}...[TRUNCATED]';
    return s;
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is String) return MapEntry(key, _sanitize(value));
      return MapEntry(key, value);
    });
  }

  Future<void> _rotateIfNeeded() async {
    final file = File(_logPath);
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    if (lines.length > _maxEntries) {
      // Garder les 80% plus recents
      final keep = (_maxEntries * 0.8).toInt();
      final toKeep = lines.sublist(lines.length - keep);
      await file.writeAsString('${toKeep.join('\n')}\n');
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Singleton :
//   final secureLog = SecureLogger(
//     logPath: '${appDataDir}/security_audit.log',
//   );
//   await secureLog.init();
//
// Logging :
//   await secureLog.log(LogSeverity.critical, 'auth',
//     'PIN incorrect - tentative #5');
//   await secureLog.log(LogSeverity.alert, 'canary',
//     'Canary token accede: ~/.ssh/id_rsa_backup');
//
// Verification d'integrite :
//   final intact = await secureLog.verifyIntegrity();
//   if (!intact) {
//     // Les logs ont ete falsifies !
//     showSecurityAlert('Logs corrompus - possible intrusion');
//   }
// =============================================================
