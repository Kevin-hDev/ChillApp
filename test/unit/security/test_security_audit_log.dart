// =============================================================
// Tests unitaires — FIX-020 : SecurityAuditLog
// Verifie : sanitisation, chaine HMAC, integrite, lecture.
// =============================================================
//
// Executer avec :
//   dart test test/unit/security/test_security_audit_log.dart
//
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:chill_app/core/security/security_audit_log.dart';

void main() {
  // Repertoire temporaire partage par tous les tests
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audit_log_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------
  // SecurityAction — structure de l'enum
  // ---------------------------------------------------------------

  group('SecurityAction', () {
    test('contient les actions requises par le cahier des charges', () {
      final requises = [
        SecurityAction.firewallEnabled,
        SecurityAction.firewallDisabled,
        SecurityAction.apparmorEnabled,
        SecurityAction.apparmorDisabled,
        SecurityAction.pinSet,
        SecurityAction.pinRemoved,
        SecurityAction.pinVerifyFailed,
        SecurityAction.daemonStarted,
        SecurityAction.daemonStopped,
        SecurityAction.sshConnected,
        SecurityAction.sshDisconnected,
        SecurityAction.debuggerDetected,
        SecurityAction.injectionDetected,
      ];
      for (final action in requises) {
        expect(SecurityAction.values, contains(action),
            reason: '${action.name} doit etre present');
      }
    });

    test('chaque action a un nom unique', () {
      final noms = SecurityAction.values.map((a) => a.name).toList();
      final unique = noms.toSet();
      expect(unique.length, equals(noms.length),
          reason: 'Pas de noms dupliques');
    });
  });

  // ---------------------------------------------------------------
  // Sanitisation
  // ---------------------------------------------------------------

  group('SecurityAuditLog.sanitize', () {
    test('supprime les chemins Unix absolus', () {
      final result = SecurityAuditLog.sanitize(
          'Erreur dans /home/user/projects/chillapp/main.dart');
      expect(result.contains('/home/user'), isFalse,
          reason: 'Chemin Unix supprime');
      expect(result.contains('[PATH]'), isTrue,
          reason: 'Remplace par [PATH]');
    });

    test('supprime les chemins Windows absolus', () {
      final result =
          SecurityAuditLog.sanitize(r'Fichier C:\Users\admin\app.exe');
      expect(result.contains('Users'), isFalse,
          reason: 'Chemin Windows supprime');
    });

    test('supprime les adresses IP non-Tailscale', () {
      final result =
          SecurityAuditLog.sanitize('Connexion depuis 192.168.1.100');
      expect(result.contains('192.168.1.100'), isFalse,
          reason: 'IP publique supprimee');
      expect(result.contains('[IP]'), isTrue,
          reason: 'Remplace par [IP]');
    });

    test('preserve les adresses IP Tailscale (100.x.x.x)', () {
      final result = SecurityAuditLog.sanitize('Connecte a 100.64.0.1');
      expect(result.contains('100.64.0.1'), isTrue,
          reason: 'IP Tailscale preservee');
    });

    test('supprime les tokens / cles base64 de 32+ caracteres', () {
      final fakeToken = 'A' * 40;
      final result = SecurityAuditLog.sanitize('Token: $fakeToken');
      expect(result.contains(fakeToken), isFalse,
          reason: 'Token supprime');
      expect(result.contains('[REDACTED]'), isTrue,
          reason: 'Remplace par [REDACTED]');
    });

    test('conserve les chaines courtes (< 32 caracteres)', () {
      final courte = 'B' * 31;
      final result = SecurityAuditLog.sanitize('Info: $courte');
      expect(result.contains(courte), isTrue,
          reason: 'Chaine courte non redactee');
    });

    test('tronque les messages depassant 200 caracteres', () {
      // Un texte long sans tokens (espaces inclus pour eviter la regex base64)
      // On construit une phrase de >200 caracteres sans sequence base64 de 32+
      final long = 'mot ' * 60; // 4 * 60 = 240 caracteres, mots courts sans base64
      final result = SecurityAuditLog.sanitize(long);
      expect(result.length, lessThanOrEqualTo(203),
          reason: '200 chars + "..." = 203 max');
      expect(result.endsWith('...'), isTrue,
          reason: 'Termine par "..."');
    });

    test('laisse passer un texte court sans modification sensible', () {
      const texte = 'Pare-feu desactive par utilisateur';
      final result = SecurityAuditLog.sanitize(texte);
      expect(result, equals(texte),
          reason: 'Texte court inoffensif inchange');
    });
  });

  // ---------------------------------------------------------------
  // Chaine de hachage HMAC
  // ---------------------------------------------------------------

  group('Chaine HMAC-SHA256', () {
    test('deux entrees successives ont des hash differents', () {
      final key = Uint8List.fromList(SecurityAuditLog.generateKey());
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final content1 =
          '2026-02-18T15:00:00.000Z|firewallDisabled|test|$genesisHash';
      final hash1 = Hmac(sha256, key).convert(utf8.encode(content1)).toString();

      final content2 =
          '2026-02-18T15:01:00.000Z|firewallEnabled|test|$hash1';
      final hash2 = Hmac(sha256, key).convert(utf8.encode(content2)).toString();

      expect(hash1, isNot(equals(hash2)),
          reason: 'Hash differents pour des contenus differents');
      expect(hash1.length, equals(64), reason: 'Hash SHA-256 = 64 hex');
      expect(hash2.length, equals(64), reason: 'Hash SHA-256 = 64 hex');
    });

    test('modification du detail invalide le hash', () {
      final key = Uint8List.fromList(SecurityAuditLog.generateKey());
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final contentOriginal =
          '2026-02-18T15:00:00.000Z|firewallDisabled|original|$genesisHash';
      final hashOriginal =
          Hmac(sha256, key).convert(utf8.encode(contentOriginal)).toString();

      final contentFalsifie =
          '2026-02-18T15:00:00.000Z|firewallDisabled|falsifie|$genesisHash';
      final hashFalsifie =
          Hmac(sha256, key).convert(utf8.encode(contentFalsifie)).toString();

      expect(hashOriginal, isNot(equals(hashFalsifie)),
          reason: 'Modification detectee par le HMAC');
    });

    test('une cle differente produit un hash different', () {
      final key1 = Uint8List.fromList(SecurityAuditLog.generateKey());
      final key2 = Uint8List.fromList(SecurityAuditLog.generateKey());
      const content = '2026-02-18T15:00:00.000Z|test|detail|genesis';

      final hash1 = Hmac(sha256, key1).convert(utf8.encode(content)).toString();
      final hash2 = Hmac(sha256, key2).convert(utf8.encode(content)).toString();

      // Il est excessivement improbable que deux cles aleatoires donnent
      // le meme hash (probabilite negligeable).
      expect(hash1, isNot(equals(hash2)),
          reason: 'Cles differentes => hash differents');
    });
  });

  // ---------------------------------------------------------------
  // Operations sur le fichier et integrite
  // ---------------------------------------------------------------

  group('SecurityAuditLog — fichier et integrite', () {
    test('open() cree le fichier si absent et log() ecrit une entree', () async {
      final logPath = '${tempDir.path}/audit.log';
      final key = SecurityAuditLog.generateKey();

      final log = await SecurityAuditLog.open(path: logPath, hmacKey: key);
      await log.log(SecurityAction.firewallDisabled, detail: 'test creation');

      final file = File(logPath);
      expect(await file.exists(), isTrue, reason: 'Fichier cree');

      final lines = await file.readAsLines();
      expect(lines.where((l) => l.trim().isNotEmpty), hasLength(1),
          reason: 'Une seule entree');

      final entry = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(entry['action'], equals('firewallDisabled'));
      expect(entry['hash'], isNotEmpty);
      expect((entry['hash'] as String).length, equals(64),
          reason: 'Hash de 64 caracteres');
    });

    test('verifyIntegrity() retourne liste vide pour un journal intact', () async {
      final logPath = '${tempDir.path}/audit_ok.log';
      final key = SecurityAuditLog.generateKey();

      final log = await SecurityAuditLog.open(path: logPath, hmacKey: key);
      await log.log(SecurityAction.firewallEnabled);
      await log.log(SecurityAction.apparmorEnabled);
      await log.log(SecurityAction.pinSet, detail: 'Configuration initiale');

      final corrupted = await log.verifyIntegrity();
      expect(corrupted, isEmpty,
          reason: 'Aucune corruption sur un journal integre');
    });

    test('verifyIntegrity() detecte une ligne modifiee manuellement', () async {
      final logPath = '${tempDir.path}/audit_tampered.log';
      final key = SecurityAuditLog.generateKey();

      final log = await SecurityAuditLog.open(path: logPath, hmacKey: key);
      await log.log(SecurityAction.firewallDisabled, detail: 'original');

      // Lire le fichier et modifier le detail
      final file = File(logPath);
      final lines = await file.readAsLines();
      final entry = jsonDecode(lines.first) as Map<String, dynamic>;
      entry['detail'] = 'falsifie'; // Modification malveillante
      await file.writeAsString('${jsonEncode(entry)}\n');

      // Ouvrir un nouveau log pour relire
      final log2 = await SecurityAuditLog.open(path: logPath, hmacKey: key);
      final corrupted = await log2.verifyIntegrity();
      expect(corrupted, isNotEmpty,
          reason: 'Modification detectee par verifyIntegrity');
    });

    test('readLast() retourne les N dernieres entrees dans l\'ordre', () async {
      final logPath = '${tempDir.path}/audit_read.log';
      final key = SecurityAuditLog.generateKey();

      final log = await SecurityAuditLog.open(path: logPath, hmacKey: key);
      await log.log(SecurityAction.daemonStarted);
      await log.log(SecurityAction.sshConnected);
      await log.log(SecurityAction.firewallEnabled);

      final entries = await log.readLast(2);
      expect(entries, hasLength(2));
      expect(entries[0].action, equals(SecurityAction.sshConnected));
      expect(entries[1].action, equals(SecurityAction.firewallEnabled));
    });

    test('generateKey() retourne toujours 32 octets', () {
      final key = SecurityAuditLog.generateKey();
      expect(key, hasLength(32), reason: 'Cle HMAC de 32 octets');
    });

    test('deux appels a generateKey() produisent des cles differentes', () {
      final key1 = SecurityAuditLog.generateKey();
      final key2 = SecurityAuditLog.generateKey();
      // Probabilite de collision negligeable avec 32 octets aleatoires
      expect(key1, isNot(equals(key2)),
          reason: 'Cles aleatoires differentes a chaque generation');
    });

    test('AuditEntry.toJson() et fromJson() font un aller-retour fidele', () {
      final ts = DateTime.utc(2026, 2, 18, 15, 0, 0);
      final entry = AuditEntry(
        timestamp: ts,
        action: SecurityAction.debuggerDetected,
        detail: 'Frida detecte',
        previousHash: '0' * 64,
        hash: 'a' * 64,
      );

      final json = entry.toJson();
      final restored = AuditEntry.fromJson(json);

      expect(restored.action, equals(entry.action));
      expect(restored.detail, equals(entry.detail));
      expect(restored.previousHash, equals(entry.previousHash));
      expect(restored.hash, equals(entry.hash));
      expect(restored.timestamp.toUtc(), equals(ts));
    });
  });
}
