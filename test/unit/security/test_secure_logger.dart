// Tests unitaires pour FIX-044 — Secure Logger Anti-Tamper
// Lance avec : flutter test test/unit/security/test_secure_logger.dart
//
// Verifie la chaine de hachage SHA-256, la sanitisation des secrets
// et la serialisation. Aucun I/O disque (tests purement en memoire).

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/secure_logger.dart';

// ---------------------------------------------------------------------------
// Helper : cree et hash une entree de log
// ---------------------------------------------------------------------------
SecureLogEntry _makeEntry({
  required SecureLogger logger,
  required int index,
  required String timestamp,
  required LogSeverity severity,
  required String category,
  required String message,
  required String previousHash,
}) {
  final entry = SecureLogEntry(
    index: index,
    timestamp: timestamp,
    severity: severity,
    category: category,
    message: message,
    previousHash: previousHash,
  );
  entry.hash = logger.computeHash(entry);
  return entry;
}

void main() {
  // ===========================================================================
  // LogSeverity enum
  // ===========================================================================

  group('LogSeverity enum', () {
    test('contient exactement 4 niveaux', () {
      expect(LogSeverity.values.length, 4);
    });

    test('contient info, warning, critical, alert', () {
      expect(LogSeverity.values, containsAll([
        LogSeverity.info,
        LogSeverity.warning,
        LogSeverity.critical,
        LogSeverity.alert,
      ]));
    });
  });

  // ===========================================================================
  // SecureLogEntry — serialisation
  // ===========================================================================

  group('SecureLogEntry — serialisation toJson/fromJson', () {
    late SecureLogger logger;

    setUp(() {
      logger = SecureLogger(logPath: '/tmp/nonexistent_test.log');
    });

    test('toJson contient tous les champs requis', () {
      final entry = _makeEntry(
        logger: logger,
        index: 42,
        timestamp: '2026-02-18T15:00:00Z',
        severity: LogSeverity.alert,
        category: 'killswitch',
        message: 'Kill switch execute',
        previousHash: 'abc123',
      );

      final json = entry.toJson();
      expect(json['index'], 42);
      expect(json['timestamp'], '2026-02-18T15:00:00Z');
      expect(json['severity'], 'alert');
      expect(json['category'], 'killswitch');
      expect(json['message'], 'Kill switch execute');
      expect(json['previous_hash'], 'abc123');
      expect(json.containsKey('hash'), isTrue);
    });

    test('fromJson reconstruit une entree identique', () {
      final entry = _makeEntry(
        logger: logger,
        index: 5,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.critical,
        category: 'auth',
        message: 'Tentative echouee',
        previousHash: 'deadbeef',
      );

      final rebuilt = SecureLogEntry.fromJson(entry.toJson());
      expect(rebuilt.index, entry.index);
      expect(rebuilt.severity, entry.severity);
      expect(rebuilt.category, entry.category);
      expect(rebuilt.message, entry.message);
      expect(rebuilt.previousHash, entry.previousHash);
      expect(rebuilt.hash, entry.hash);
    });

    test('severite est serialisee par son nom (string)', () {
      for (final sev in LogSeverity.values) {
        final entry = _makeEntry(
          logger: logger,
          index: 0,
          timestamp: '2026-01-01T00:00:00Z',
          severity: sev,
          category: 'test',
          message: 'msg',
          previousHash: '0' * 64,
        );
        expect(entry.toJson()['severity'], sev.name);
      }
    });

    test('metadata null est inclus dans toJson', () {
      final entry = SecureLogEntry(
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'sans meta',
        previousHash: '0' * 64,
      );
      entry.hash = logger.computeHash(entry);

      expect(entry.toJson()['metadata'], isNull);
    });
  });

  // ===========================================================================
  // Chaine de hachage SHA-256
  // ===========================================================================

  group('Chaine de hachage SHA-256', () {
    late SecureLogger logger;
    const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

    setUp(() {
      logger = SecureLogger(logPath: '/tmp/nonexistent_test.log');
    });

    test('hash du genesis block a 64 caracteres hexadecimaux', () {
      final entry = _makeEntry(
        logger: logger,
        index: 0,
        timestamp: '2026-02-18T15:00:00.000Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'Premier log',
        previousHash: genesisHash,
      );

      expect(entry.hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.hash), isTrue);
    });

    test('le hash est deterministe pour les memes donnees', () {
      final e1 = _makeEntry(
        logger: logger,
        index: 5,
        timestamp: '2026-02-18T12:00:00Z',
        severity: LogSeverity.critical,
        category: 'auth',
        message: 'test msg',
        previousHash: 'a' * 64,
      );
      final e2 = _makeEntry(
        logger: logger,
        index: 5,
        timestamp: '2026-02-18T12:00:00Z',
        severity: LogSeverity.critical,
        category: 'auth',
        message: 'test msg',
        previousHash: 'a' * 64,
      );
      expect(e1.hash, e2.hash);
    });

    test('changer un seul caractere change le hash', () {
      final base = _makeEntry(
        logger: logger,
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'hello',
        previousHash: '0' * 64,
      );
      final modified = _makeEntry(
        logger: logger,
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'hellO',
        previousHash: '0' * 64,
      );
      expect(base.hash, isNot(modified.hash));
    });

    test('la chaine lie chaque entree a la precedente', () {
      var prevHash = genesisHash;
      final entries = <SecureLogEntry>[];

      for (int i = 0; i < 3; i++) {
        final entry = _makeEntry(
          logger: logger,
          index: i,
          timestamp: '2026-01-01T00:0$i:00Z',
          severity: LogSeverity.info,
          category: 'test',
          message: 'entry $i',
          previousHash: prevHash,
        );
        entries.add(entry);
        prevHash = entry.hash;
      }

      // Verifier que chaque previousHash correspond au hash precedent.
      expect(entries[0].previousHash, genesisHash);
      expect(entries[1].previousHash, entries[0].hash);
      expect(entries[2].previousHash, entries[1].hash);
    });

    test('tamper au milieu rompt la chaine', () {
      var prevHash = genesisHash;
      final entries = <SecureLogEntry>[];

      for (int i = 0; i < 3; i++) {
        final entry = _makeEntry(
          logger: logger,
          index: i,
          timestamp: '2026-01-01T00:0$i:00Z',
          severity: LogSeverity.info,
          category: 'test',
          message: 'entry $i',
          previousHash: prevHash,
        );
        entries.add(entry);
        prevHash = entry.hash;
      }

      // Tamper l'entree 1.
      final tampered = _makeEntry(
        logger: logger,
        index: 1,
        timestamp: '2026-01-01T00:01:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'TAMPERED',
        previousHash: entries[0].hash,
      );

      // Le hash de l'entree 2 ne correspond plus au hash tampered.
      expect(entries[2].previousHash, isNot(tampered.hash));
    });

    test('modifier une entree rend son hash different', () {
      final original = _makeEntry(
        logger: logger,
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'original',
        previousHash: '0' * 64,
      );

      final tampered = SecureLogEntry(
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'TAMPERED',
        previousHash: '0' * 64,
      );
      tampered.hash = logger.computeHash(tampered);

      expect(original.hash, isNot(tampered.hash));
    });
  });

  // ===========================================================================
  // Sanitisation des secrets
  // ===========================================================================

  group('SecureLogger.sanitize — suppression des secrets', () {
    late SecureLogger logger;

    setUp(() {
      logger = SecureLogger(logPath: '/tmp/nonexistent_test.log');
    });

    test('supprime les cles SSH (BEGIN/END KEY)', () {
      const msg = 'Key: -----BEGIN OPENSSH PRIVATE KEY-----\nbase64data\n-----END OPENSSH PRIVATE KEY-----';
      final result = logger.sanitize(msg);
      expect(result, contains('[KEY_REDACTED]'));
      expect(result, isNot(contains('base64data')));
    });

    test('supprime les tokens longs (>= 40 caracteres base64)', () {
      final token = 'A' * 50;
      final result = logger.sanitize('Token: $token');
      expect(result, contains('[TOKEN_REDACTED]'));
      expect(result, isNot(contains(token)));
    });

    test('les tokens courts (< 40 chars) ne sont pas rediges', () {
      final short = 'A' * 39;
      final result = logger.sanitize('Token: $short');
      expect(result, contains(short));
    });

    test('supprime les mots de passe (password=xxx)', () {
      final result = logger.sanitize('password=secret123');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('secret123')));
    });

    test('supprime les mots de passe (Password:xxx)', () {
      final result = logger.sanitize('Password:admin');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('admin')));
    });

    test('masque les chemins utilisateur Linux', () {
      final result = logger.sanitize('/home/kevin/.ssh/id_rsa');
      expect(result, contains('/home/[USER]'));
      expect(result, isNot(contains('kevin')));
    });

    test('masque les chemins utilisateur Windows', () {
      final result = logger.sanitize(r'C:\Users\admin\Documents');
      expect(result, contains('[USER]'));
      expect(result, isNot(contains('admin')));
    });

    test('masque les IPs privees non-Tailscale', () {
      expect(logger.sanitize('Source: 192.168.1.100'), contains('[IP_REDACTED]'));
      expect(logger.sanitize('Source: 10.0.0.1'), contains('[IP_REDACTED]'));
      expect(logger.sanitize('Source: 172.16.0.1'), contains('[IP_REDACTED]'));
    });

    test('preserve les IPs Tailscale (100.64.x.x - 100.127.x.x)', () {
      final result = logger.sanitize('Tailscale: 100.64.0.1');
      // L'IP Tailscale ne doit PAS etre masquee.
      expect(result, contains('100.64.0.1'));
    });

    test('preserve les autres IPs Tailscale valides', () {
      expect(logger.sanitize('ip: 100.100.0.1'), contains('100.100.0.1'));
      expect(logger.sanitize('ip: 100.127.255.1'), contains('100.127.255.1'));
    });

    test('tronque les messages trop longs (> 500 chars)', () {
      // Utiliser des espaces pour eviter la regex des tokens longs (40+ alphanum)
      // Un message de 600 chars avec des mots courts et espaces.
      final longMsg = ('abc ' * 150).trimRight(); // 600 chars avec espaces
      final result = logger.sanitize(longMsg);
      expect(result.length, lessThan(longMsg.length));
      expect(result, contains('[TRUNCATED]'));
    });

    test('les messages courts ne sont pas tronques', () {
      const msg = 'Court message de securite';
      expect(logger.sanitize(msg), msg);
    });

    test('message vide reste vide', () {
      expect(logger.sanitize(''), '');
    });
  });

  // ===========================================================================
  // SecureLogger — construction
  // ===========================================================================

  group('SecureLogger — construction', () {
    test('se cree avec un logPath', () {
      expect(
        () => SecureLogger(logPath: '/tmp/test_secure.log'),
        returnsNormally,
      );
    });

    test('maxEntries personnalise est accepte', () {
      expect(
        () => SecureLogger(logPath: '/tmp/test.log', maxEntries: 1000),
        returnsNormally,
      );
    });
  });

  // ===========================================================================
  // SecureLogger — buffer en memoire (sans I/O)
  // ===========================================================================

  group('SecureLogger — log en memoire (sans flush)', () {
    test('computeHash retourne une chaine de 64 caracteres hex', () {
      final logger = SecureLogger(logPath: '/tmp/test.log');
      final entry = SecureLogEntry(
        index: 0,
        timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'hello',
        previousHash: '0' * 64,
      );
      final hash = logger.computeHash(entry);
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('deux appels a computeHash avec les memes donnees retournent le meme hash', () {
      final logger = SecureLogger(logPath: '/tmp/test.log');
      final entry = SecureLogEntry(
        index: 1,
        timestamp: '2026-02-18T10:00:00Z',
        severity: LogSeverity.warning,
        category: 'ssh',
        message: 'Connexion refusee',
        previousHash: 'cafebabe' * 8,
      );
      expect(logger.computeHash(entry), logger.computeHash(entry));
    });
  });
}
