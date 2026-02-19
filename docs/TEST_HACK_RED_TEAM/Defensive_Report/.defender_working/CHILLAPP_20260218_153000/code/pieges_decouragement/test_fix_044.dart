// =============================================================
// TEST FIX-044 : Secure Logger Anti-Tamper
// Verification de la chaine de hachage et de la sanitisation
// =============================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

// Reproduction des types pour les tests
enum LogSeverity { info, warning, critical, alert }

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
}

String computeHash(SecureLogEntry entry) {
  final data = '${entry.index}|${entry.timestamp}|'
      '${entry.severity.name}|${entry.category}|'
      '${entry.message}|${entry.previousHash}';
  return sha256.convert(utf8.encode(data)).toString();
}

String sanitize(String message) {
  var s = message;
  s = s.replaceAll(
    RegExp(r'-----BEGIN.*KEY-----[\s\S]*?-----END.*KEY-----'),
    '[KEY_REDACTED]');
  s = s.replaceAll(RegExp(r'[A-Za-z0-9+/=]{40,}'), '[TOKEN_REDACTED]');
  s = s.replaceAll(
    RegExp(r'password[=:]\S+', caseSensitive: false),
    'password=[REDACTED]');
  s = s.replaceAll(RegExp(r'/home/\w+'), '/home/[USER]');
  s = s.replaceAll(RegExp(r'C:\\Users\\\w+'), r'C:\Users\[USER]');
  s = s.replaceAll(
    RegExp(r'\b(?!100\.(?:6[4-9]|[7-9]\d|1[0-1]\d|12[0-7])\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
    '[IP_REDACTED]');
  if (s.length > 500) s = '${s.substring(0, 500)}...[TRUNCATED]';
  return s;
}

void main() {
  group('Chaine de hachage SHA-256', () {
    test('hash du genesis block (index 0) est deterministe', () {
      final genesis = '0' * 64;
      final entry = SecureLogEntry(
        index: 0,
        timestamp: '2026-02-18T15:00:00.000Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'Premier log',
        previousHash: genesis,
      );
      entry.hash = computeHash(entry);

      expect(entry.hash, isNotEmpty);
      expect(entry.hash.length, 64); // SHA-256 = 64 hex chars
    });

    test('chaine de hachage est liee : hash N depend de hash N-1', () {
      final genesis = '0' * 64;

      final entry0 = SecureLogEntry(
        index: 0, timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info, category: 'test',
        message: 'entry 0', previousHash: genesis,
      );
      entry0.hash = computeHash(entry0);

      final entry1 = SecureLogEntry(
        index: 1, timestamp: '2026-01-01T00:01:00Z',
        severity: LogSeverity.warning, category: 'test',
        message: 'entry 1', previousHash: entry0.hash,
      );
      entry1.hash = computeHash(entry1);

      // Modifier entry0 doit invalider entry1
      final fakeEntry0 = SecureLogEntry(
        index: 0, timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info, category: 'test',
        message: 'TAMPERED entry', previousHash: genesis,
      );
      fakeEntry0.hash = computeHash(fakeEntry0);

      expect(fakeEntry0.hash, isNot(entry0.hash));
      // entry1.previousHash ne correspond plus
      expect(entry1.previousHash, isNot(fakeEntry0.hash));
    });

    test('meme entree = meme hash (deterministe)', () {
      final entry = SecureLogEntry(
        index: 5, timestamp: '2026-02-18T12:00:00Z',
        severity: LogSeverity.critical, category: 'auth',
        message: 'test msg', previousHash: 'a' * 64,
      );
      final hash1 = computeHash(entry);
      final hash2 = computeHash(entry);
      expect(hash1, hash2);
    });

    test('changer un seul caractere change le hash', () {
      final base = SecureLogEntry(
        index: 0, timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info, category: 'test',
        message: 'hello', previousHash: '0' * 64,
      );
      final modified = SecureLogEntry(
        index: 0, timestamp: '2026-01-01T00:00:00Z',
        severity: LogSeverity.info, category: 'test',
        message: 'hellO', previousHash: '0' * 64,
      );
      expect(computeHash(base), isNot(computeHash(modified)));
    });
  });

  group('Verification integrite', () {
    test('chaine valide de 3 entrees se verifie', () {
      final genesis = '0' * 64;
      final entries = <SecureLogEntry>[];

      var prevHash = genesis;
      for (int i = 0; i < 3; i++) {
        final entry = SecureLogEntry(
          index: i,
          timestamp: '2026-01-01T00:0$i:00Z',
          severity: LogSeverity.info,
          category: 'test',
          message: 'entry $i',
          previousHash: prevHash,
        );
        entry.hash = computeHash(entry);
        entries.add(entry);
        prevHash = entry.hash;
      }

      // Verifier la chaine
      var prev = genesis;
      bool valid = true;
      for (final entry in entries) {
        if (entry.previousHash != prev) { valid = false; break; }
        if (computeHash(entry) != entry.hash) { valid = false; break; }
        prev = entry.hash;
      }
      expect(valid, isTrue);
    });

    test('tamper au milieu est detecte', () {
      final genesis = '0' * 64;
      final entries = <SecureLogEntry>[];

      var prevHash = genesis;
      for (int i = 0; i < 3; i++) {
        final entry = SecureLogEntry(
          index: i,
          timestamp: '2026-01-01T00:0$i:00Z',
          severity: LogSeverity.info,
          category: 'test',
          message: 'entry $i',
          previousHash: prevHash,
        );
        entry.hash = computeHash(entry);
        entries.add(entry);
        prevHash = entry.hash;
      }

      // Tamper l'entree 1
      entries[1] = SecureLogEntry(
        index: 1,
        timestamp: '2026-01-01T00:01:00Z',
        severity: LogSeverity.info,
        category: 'test',
        message: 'TAMPERED',
        previousHash: entries[0].hash,
      );
      entries[1].hash = computeHash(entries[1]);

      // L'entree 2 n'est plus valide (previousHash ne correspond plus)
      expect(entries[2].previousHash, isNot(entries[1].hash));
    });
  });

  group('Sanitisation des logs', () {
    test('supprime les cles SSH', () {
      const msg = 'Key: -----BEGIN OPENSSH PRIVATE KEY-----\nbase64data\n-----END OPENSSH PRIVATE KEY-----';
      expect(sanitize(msg), contains('[KEY_REDACTED]'));
      expect(sanitize(msg), isNot(contains('base64data')));
    });

    test('supprime les tokens longs (> 40 chars)', () {
      final token = 'A' * 50;
      expect(sanitize('Token: $token'), contains('[TOKEN_REDACTED]'));
    });

    test('supprime les mots de passe', () {
      expect(sanitize('password=secret123'), contains('[REDACTED]'));
      expect(sanitize('password=secret123'), isNot(contains('secret123')));
      expect(sanitize('Password:admin'), contains('[REDACTED]'));
    });

    test('masque les chemins utilisateur Linux', () {
      expect(sanitize('/home/kevin/.ssh/id_rsa'), contains('/home/[USER]'));
      expect(sanitize('/home/kevin/.ssh/id_rsa'), isNot(contains('kevin')));
    });

    test('masque les chemins utilisateur Windows', () {
      expect(sanitize(r'C:\Users\admin\Documents'), contains('[USER]'));
    });

    test('masque les IPs non-Tailscale', () {
      expect(sanitize('Source: 192.168.1.100'), contains('[IP_REDACTED]'));
      expect(sanitize('Source: 10.0.0.1'), contains('[IP_REDACTED]'));
    });

    test('preserve les IPs Tailscale (100.64-127.x.x)', () {
      final result = sanitize('Tailscale: 100.64.0.1');
      // L'IP Tailscale ne doit PAS etre masquee
      expect(result, contains('100.64.0.1'));
    });

    test('tronque a 500 caracteres', () {
      final longMsg = 'x' * 600;
      final result = sanitize(longMsg);
      expect(result.length, lessThan(600));
      expect(result, contains('[TRUNCATED]'));
    });

    test('messages courts ne sont pas tronques', () {
      const msg = 'Court message de log';
      expect(sanitize(msg), msg);
    });
  });

  group('SecureLogEntry serialisation', () {
    test('toJson contient tous les champs', () {
      final entry = SecureLogEntry(
        index: 42,
        timestamp: '2026-02-18T15:00:00Z',
        severity: LogSeverity.alert,
        category: 'killswitch',
        message: 'Kill switch execute',
        previousHash: 'abc123',
      );
      entry.hash = 'def456';

      final json = entry.toJson();
      expect(json['index'], 42);
      expect(json['severity'], 'alert');
      expect(json['category'], 'killswitch');
      expect(json['previous_hash'], 'abc123');
      expect(json['hash'], 'def456');
    });
  });
}
