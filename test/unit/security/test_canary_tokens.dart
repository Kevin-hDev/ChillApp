// Tests unitaires pour FIX-042 — Canary Tokens
// Lance avec : flutter test test/unit/security/test_canary_tokens.dart
//
// Les tests couvrent la logique pure (types, serialisation, verification)
// sans ecrire de vrais fichiers sur le systeme.

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/canary_tokens.dart';

void main() {
  // ===========================================================================
  // CanaryType — enum
  // ===========================================================================

  group('CanaryType enum', () {
    test('contient exactement 4 valeurs', () {
      expect(CanaryType.values.length, 4);
    });

    test('contient toutes les valeurs attendues', () {
      expect(CanaryType.values, containsAll([
        CanaryType.fakeSSHKey,
        CanaryType.fakeCredentials,
        CanaryType.fakeDatabase,
        CanaryType.fakeEnvFile,
      ]));
    });
  });

  // ===========================================================================
  // CanaryStatus — enum
  // ===========================================================================

  group('CanaryStatus enum', () {
    test('contient exactement 4 valeurs', () {
      expect(CanaryStatus.values.length, 4);
    });

    test('contient intact, accessed, modified, deleted', () {
      expect(CanaryStatus.values, containsAll([
        CanaryStatus.intact,
        CanaryStatus.accessed,
        CanaryStatus.modified,
        CanaryStatus.deleted,
      ]));
    });
  });

  // ===========================================================================
  // CanaryRecord — serialisation
  // ===========================================================================

  group('CanaryRecord — serialisation JSON', () {
    late CanaryRecord record;

    setUp(() {
      record = CanaryRecord(
        path: '/home/user/.ssh/id_rsa_backup',
        type: CanaryType.fakeSSHKey,
        deployedAt: DateTime.utc(2026, 2, 18, 12, 0, 0),
        contentHash: 'abc123def456',
      );
    });

    test('toJson contient tous les champs requis', () {
      final json = record.toJson();
      expect(json.containsKey('path'), isTrue);
      expect(json.containsKey('type'), isTrue);
      expect(json.containsKey('deployed_at'), isTrue);
      expect(json.containsKey('content_hash'), isTrue);
    });

    test('toJson serialise le type par son nom', () {
      final json = record.toJson();
      expect(json['type'], 'fakeSSHKey');
    });

    test('toJson serialise la date en ISO8601', () {
      final json = record.toJson();
      expect(json['deployed_at'], '2026-02-18T12:00:00.000Z');
    });

    test('fromJson reconstruit un CanaryRecord identique', () {
      final json = record.toJson();
      final rebuilt = CanaryRecord.fromJson(json);

      expect(rebuilt.path, record.path);
      expect(rebuilt.type, record.type);
      expect(rebuilt.deployedAt, record.deployedAt);
      expect(rebuilt.contentHash, record.contentHash);
    });

    test('fromJson fonctionne pour tous les types de canary', () {
      for (final type in CanaryType.values) {
        final r = CanaryRecord(
          path: '/tmp/canary_${type.name}',
          type: type,
          deployedAt: DateTime.now(),
          contentHash: 'hash_${type.name}',
        );
        final rebuilt = CanaryRecord.fromJson(r.toJson());
        expect(rebuilt.type, type);
      }
    });
  });

  // ===========================================================================
  // CanaryCheckResult — logique isTriggered
  // ===========================================================================

  group('CanaryCheckResult — isTriggered', () {
    late CanaryRecord baseRecord;

    setUp(() {
      baseRecord = CanaryRecord(
        path: '/tmp/canary_test',
        type: CanaryType.fakeCredentials,
        deployedAt: DateTime.now(),
        contentHash: 'hash123',
      );
    });

    test('status intact => isTriggered est false', () {
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.intact,
      );
      expect(result.isTriggered, isFalse);
    });

    test('status accessed => isTriggered est true', () {
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.accessed,
      );
      expect(result.isTriggered, isTrue);
    });

    test('status modified => isTriggered est true', () {
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.modified,
      );
      expect(result.isTriggered, isTrue);
    });

    test('status deleted => isTriggered est true', () {
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.deleted,
      );
      expect(result.isTriggered, isTrue);
    });

    test('lastAccessed peut etre null (statut intact)', () {
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.intact,
      );
      expect(result.lastAccessed, isNull);
    });

    test('lastAccessed est rempli pour un acces detecte', () {
      final accessTime = DateTime.now();
      final result = CanaryCheckResult(
        record: baseRecord,
        status: CanaryStatus.accessed,
        lastAccessed: accessTime,
      );
      expect(result.lastAccessed, accessTime);
    });
  });

  // ===========================================================================
  // CanaryTokenManager — initialisation et registre
  // ===========================================================================

  group('CanaryTokenManager — initialisation', () {
    test('se cree sans parametres obligatoires', () {
      expect(() => CanaryTokenManager(), returnsNormally);
    });

    test('accepte un registryPath personnalise', () {
      final manager = CanaryTokenManager(registryPath: '/tmp/test_registry');
      expect(manager, isNotNull);
    });

    test('records est vide a la creation', () {
      final manager = CanaryTokenManager(registryPath: '/tmp/test_registry');
      expect(manager.records, isEmpty);
    });

    test('records retourne une liste immuable', () {
      final manager = CanaryTokenManager(registryPath: '/tmp/test_registry');
      final fakeRecord = CanaryRecord(
        path: '/tmp/fake',
        type: CanaryType.fakeSSHKey,
        deployedAt: DateTime.now(),
        contentHash: 'abc',
      );
      expect(
        () => manager.records.add(fakeRecord),
        throwsUnsupportedError,
      );
    });

    test('callback onAlert peut etre assigne', () {
      CanaryCheckResult? captured;
      final manager = CanaryTokenManager(
        registryPath: '/tmp/test_registry',
        onAlert: (result) => captured = result,
      );

      expect(captured, isNull);
      expect(manager.onAlert, isNotNull);
    });
  });

  // ===========================================================================
  // CanaryTokenManager — callback onAlert
  // ===========================================================================

  group('CanaryTokenManager — callback onAlert', () {
    test('onAlert est appele uniquement si isTriggered est true', () {
      final alerts = <CanaryCheckResult>[];
      final manager = CanaryTokenManager(
        registryPath: '/tmp/test_noop',
        onAlert: alerts.add,
      );

      final record = CanaryRecord(
        path: '/tmp/fake_key',
        type: CanaryType.fakeSSHKey,
        deployedAt: DateTime.now(),
        contentHash: 'abc',
      );

      // Simuler une alerte en appelant directement onAlert
      final intactResult = CanaryCheckResult(
        record: record,
        status: CanaryStatus.intact,
      );
      final triggeredResult = CanaryCheckResult(
        record: record,
        status: CanaryStatus.accessed,
      );

      // intact ne devrait pas etre transmis automatiquement
      if (intactResult.isTriggered) manager.onAlert?.call(intactResult);
      // accessed doit declencher l'alerte
      if (triggeredResult.isTriggered) manager.onAlert?.call(triggeredResult);

      expect(alerts.length, 1);
      expect(alerts.first.status, CanaryStatus.accessed);
    });
  });
}
