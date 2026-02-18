// FIX-044 : Secure Logging Anti-Tamper
// GAP-044: Secure logging anti-tamper absent (P1)
// Journal securise avec chaine de hachage SHA-256 (blockchain-like),
// sanitisation automatique des secrets et export forensique.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Niveau de severite d'un evenement de securite.
enum LogSeverity {
  info,
  warning,
  critical,
  alert,
}

/// Entree de log securisee avec chaine de hachage anti-tamper.
///
/// Chaque entree reference le hash de l'entree precedente, formant une
/// chaine. Toute modification d'une entree invalide toutes les entrees
/// suivantes, rendant la falsification detectable.
class SecureLogEntry {
  final int index;
  final String timestamp;
  final LogSeverity severity;
  final String category;
  final String message;
  final Map<String, dynamic>? metadata;
  final String previousHash;

  /// Hash SHA-256 de cette entree (inclut le previousHash).
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
      severity: LogSeverity.values
          .firstWhere((s) => s.name == json['severity'] as String),
      category: json['category'] as String,
      message: json['message'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      previousHash: json['previous_hash'] as String,
    );
    entry.hash = json['hash'] as String;
    return entry;
  }

  @override
  String toString() =>
      'SecureLogEntry(#$index ${severity.name} [$category] $message)';
}

/// Logger securise avec chaine de hachage SHA-256 anti-tamper.
///
/// Fonctionnalites :
/// - Chaine de hachage : chaque entree depend du hash precedent.
/// - Sanitisation automatique : supprime cles SSH, tokens, mots de passe, IPs.
/// - Buffer de 10 entrees + flush sur demande ou automatique.
/// - Rotation apres [_maxEntries] entrees (conserve 80% des plus recentes).
/// - [verifyIntegrity] : verifie toute la chaine.
/// - [exportForForensics] : export JSON complet pour investigation.
class SecureLogger {
  final String _logPath;
  final int _maxEntries;

  String _previousHash = _genesisHash;
  int _index = 0;
  final List<SecureLogEntry> _buffer = [];

  /// Nombre d'entrees dans le buffer avant flush automatique.
  static const int _flushThreshold = 10;

  /// Hash initial de la chaine (genesis block).
  static const String _genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

  SecureLogger({
    required String logPath,
    int maxEntries = 50000,
  })  : _logPath = logPath,
        _maxEntries = maxEntries;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Charge l'etat precedent depuis le fichier de log existant.
  ///
  /// Si le fichier est corrompu, repart de zero (pas d'arret silencieux).
  Future<void> init() async {
    final file = File(_logPath);
    if (!await file.exists()) return;

    try {
      final lines = await file.readAsLines();
      if (lines.isNotEmpty) {
        // Trouver la derniere ligne non vide.
        final lastLine =
            lines.reversed.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (lastLine.isNotEmpty) {
          final lastEntry = SecureLogEntry.fromJson(
            jsonDecode(lastLine) as Map<String, dynamic>,
          );
          _previousHash = lastEntry.hash;
          _index = lastEntry.index + 1;
        }
      }
    } catch (_) {
      // Fichier corrompu — repartir de zero.
      _previousHash = _genesisHash;
      _index = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Ajoute une entree de log sanitisee dans la chaine.
  Future<void> log(
    LogSeverity severity,
    String category,
    String message, {
    Map<String, dynamic>? metadata,
  }) async {
    final sanitizedMessage = sanitize(message);
    final sanitizedMeta =
        metadata != null ? _sanitizeMap(metadata) : null;

    final entry = SecureLogEntry(
      index: _index,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      severity: severity,
      category: category,
      message: sanitizedMessage,
      metadata: sanitizedMeta,
      previousHash: _previousHash,
    );

    entry.hash = computeHash(entry);
    _previousHash = entry.hash;
    _index++;

    _buffer.add(entry);

    if (_buffer.length >= _flushThreshold) {
      await flush();
    }
  }

  /// Ecrit le buffer sur disque immediatement.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    final file = File(_logPath);
    await file.parent.create(recursive: true);

    final lines = _buffer.map((e) => jsonEncode(e.toJson())).join('\n');
    await file.writeAsString('$lines\n', mode: FileMode.append);

    // Permissions restrictives.
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', _logPath]);
    }

    _buffer.clear();

    await _rotateIfNeeded();
  }

  // ---------------------------------------------------------------------------
  // Verification et export
  // ---------------------------------------------------------------------------

  /// Verifie l'integrite de toute la chaine de logs sur disque.
  ///
  /// Retourne false des qu'une entree est invalide ou que la chaine est rompue.
  Future<bool> verifyIntegrity() async {
    // Les entrees en buffer ne sont pas encore sur disque — la chaine est
    // toujours integre si le buffer est vide ou si le fichier n'existe pas.
    final file = File(_logPath);
    if (!await file.exists()) return true;

    try {
      final lines = await file.readAsLines();
      String prevHash = _genesisHash;

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final entry = SecureLogEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );

        // Verifier le lien avec l'entree precedente.
        if (entry.previousHash != prevHash) return false;

        // Verifier le hash de l'entree elle-meme.
        final computed = computeHash(entry);
        if (computed != entry.hash) return false;

        prevHash = entry.hash;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Exporte tous les logs pour analyse forensique (JSON indenté).
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

  // ---------------------------------------------------------------------------
  // Hachage (exposé pour les tests)
  // ---------------------------------------------------------------------------

  /// Calcule le hash SHA-256 d'une entree de log.
  String computeHash(SecureLogEntry entry) {
    final metaStr = entry.metadata != null
        ? jsonEncode(entry.metadata)
        : '';
    final data = '${entry.index}|${entry.timestamp}|'
        '${entry.severity.name}|${entry.category}|'
        '${entry.message}|$metaStr|${entry.previousHash}';
    return sha256.convert(utf8.encode(data)).toString();
  }

  // ---------------------------------------------------------------------------
  // Sanitisation (exposée pour les tests)
  // ---------------------------------------------------------------------------

  /// Supprime les informations sensibles d'un message.
  ///
  /// Patterns rediges :
  /// - Cles SSH (BEGIN/END KEY)
  /// - Tokens longs > 40 caracteres base64
  /// - Mots de passe (password=xxx, Password:xxx)
  /// - Chemins utilisateur Linux (/home/user) et Windows (C:\Users\user)
  /// - IPs non-Tailscale (preserves : 100.64.x.x – 100.127.x.x)
  /// - Troncature a 500 caracteres
  String sanitize(String message) {
    var s = message;

    // Cles SSH / PGP / certificates.
    s = s.replaceAll(
      RegExp(
        r'-----BEGIN.*?KEY-----[\s\S]*?-----END.*?KEY-----',
        caseSensitive: false,
      ),
      '[KEY_REDACTED]',
    );

    // Tokens longs (> 40 chars de base64/hex).
    s = s.replaceAll(
      RegExp(r'[A-Za-z0-9+/=]{40,}'),
      '[TOKEN_REDACTED]',
    );

    // Mots de passe.
    s = s.replaceAll(
      RegExp(r'password[=:]\S+', caseSensitive: false),
      'password=[REDACTED]',
    );

    // Chemins utilisateur Linux.
    s = s.replaceAll(
      RegExp(r'/home/\w+'),
      '/home/[USER]',
    );

    // Chemins utilisateur Windows.
    s = s.replaceAll(
      RegExp(r'C:\\Users\\\w+'),
      r'C:\Users\[USER]',
    );

    // IPs non-Tailscale.
    // Preserve : 100.64.x.x → 100.127.x.x (plage CGNAT Tailscale).
    s = s.replaceAll(
      RegExp(
        r'\b(?!100\.(?:6[4-9]|[7-9]\d|1[0-1]\d|12[0-7])\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
      ),
      '[IP_REDACTED]',
    );

    // Troncature.
    if (s.length > 500) {
      s = '${s.substring(0, 500)}...[TRUNCATED]';
    }

    return s;
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is String) return MapEntry(key, sanitize(value));
      return MapEntry(key, value);
    });
  }

  // ---------------------------------------------------------------------------
  // Rotation
  // ---------------------------------------------------------------------------

  Future<void> _rotateIfNeeded() async {
    final file = File(_logPath);
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    if (lines.length > _maxEntries) {
      // Garder les 80% plus recents.
      final keep = (_maxEntries * 0.8).toInt();
      final toKeep = lines.sublist(lines.length - keep);
      await file.writeAsString('${toKeep.join('\n')}\n');
    }
  }
}
