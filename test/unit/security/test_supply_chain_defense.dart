// Tests FIX-056 : Supply Chain Defense (slopsquatting)
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/supply_chain_defense.dart';

void main() {
  // =========================================================
  // PackageAuditResult
  // =========================================================
  group('PackageAuditResult', () {
    test('isCritical retourne true uniquement pour severity = critical', () {
      expect(
        const PackageAuditResult(
          name: 'bad-pkg',
          version: '1.0.0',
          severity: 'critical',
          message: 'Typosquatting',
        ).isCritical,
        isTrue,
      );
      expect(
        const PackageAuditResult(
          name: 'pkg',
          version: '1.0.0',
          severity: 'warning',
          message: 'Git source',
        ).isCritical,
        isFalse,
      );
    });

    test('isWarning retourne true uniquement pour severity = warning', () {
      expect(
        const PackageAuditResult(
          name: 'pkg',
          version: '1.0.0',
          severity: 'warning',
          message: 'Git source',
        ).isWarning,
        isTrue,
      );
      expect(
        const PackageAuditResult(
          name: 'pkg',
          version: '1.0.0',
          severity: 'info',
          message: 'Unknown package',
        ).isWarning,
        isFalse,
      );
    });

    test('toString inclut le nom et la severite', () {
      const result = PackageAuditResult(
        name: 'flutter-widgets',
        version: '1.0.0',
        severity: 'critical',
        message: 'Typosquatting',
      );
      expect(result.toString(), contains('critical'));
      expect(result.toString(), contains('flutter-widgets'));
    });
  });

  // =========================================================
  // Constantes de classe
  // =========================================================
  group('SupplyChainDefense — packages de confiance', () {
    test('contient les packages principaux de ChillApp', () {
      expect(SupplyChainDefense.trustedPackages, contains('flutter_riverpod'));
      expect(SupplyChainDefense.trustedPackages, contains('go_router'));
      expect(SupplyChainDefense.trustedPackages, contains('crypto'));
      expect(SupplyChainDefense.trustedPackages, contains('shared_preferences'));
      expect(SupplyChainDefense.trustedPackages, contains('google_fonts'));
    });

    test('patterns suspects contient les typos connues', () {
      expect(SupplyChainDefense.suspiciousPatterns, contains('flutter-'));
      expect(SupplyChainDefense.suspiciousPatterns, contains('flutterr'));
      expect(SupplyChainDefense.suspiciousPatterns, contains('riverpood'));
      expect(SupplyChainDefense.suspiciousPatterns, contains('cripto'));
    });
  });

  // =========================================================
  // auditPackageList (sans I/O)
  // =========================================================
  group('SupplyChainDefense.auditPackageList', () {
    test('retourne ok quand tous les packages sont de confiance', () {
      final results = SupplyChainDefense.auditPackageList([
        {'name': 'flutter_riverpod', 'version': '3.2.1', 'source': 'hosted'},
        {'name': 'go_router', 'version': '16.2.2', 'source': 'hosted'},
        {'name': 'crypto', 'version': '3.0.7', 'source': 'hosted'},
      ]);
      expect(results, hasLength(1));
      expect(results.first.severity, equals('ok'));
    });

    test('detecte flutter- comme typosquatting (critical)', () {
      final results = SupplyChainDefense.auditPackageList([
        {
          'name': 'flutter-widgets-pro',
          'version': '1.0.0',
          'source': 'hosted',
        },
      ]);
      final critical = results.where((r) => r.severity == 'critical').toList();
      expect(critical, isNotEmpty);
      expect(critical.first.name, equals('flutter-widgets-pro'));
    });

    test('detecte flutterr comme typosquatting (critical)', () {
      final results = SupplyChainDefense.auditPackageList([
        {'name': 'flutterr_state', 'version': '1.0.0', 'source': 'hosted'},
      ]);
      expect(results.any((r) => r.severity == 'critical'), isTrue);
    });

    test('detecte riverpood comme typosquatting (critical)', () {
      final results = SupplyChainDefense.auditPackageList([
        {'name': 'riverpood', 'version': '2.0.0', 'source': 'hosted'},
      ]);
      expect(results.any((r) => r.severity == 'critical'), isTrue);
    });

    test('detecte cripto comme typosquatting (critical)', () {
      final results = SupplyChainDefense.auditPackageList([
        {'name': 'cripto', 'version': '1.0.0', 'source': 'hosted'},
      ]);
      expect(results.any((r) => r.severity == 'critical'), isTrue);
    });

    test('signale un package git comme warning', () {
      final results = SupplyChainDefense.auditPackageList([
        {
          'name': 'my_custom_pkg',
          'version': '0.0.1',
          'source': 'git',
        },
      ]);
      expect(results.any((r) => r.severity == 'warning'), isTrue);
    });

    test('signale un package path comme info', () {
      final results = SupplyChainDefense.auditPackageList([
        {
          'name': 'local_widget',
          'version': '1.0.0',
          'source': 'path',
        },
      ]);
      expect(results.any((r) => r.severity == 'info'), isTrue);
    });

    test('les packages SDK sont ignores', () {
      final results = SupplyChainDefense.auditPackageList([
        {
          'name': 'flutter',
          'version': '3.38.7',
          'source': 'sdk',
        },
      ]);
      // Le package SDK ne doit pas generer de warning ou critical
      expect(results.any((r) => r.severity == 'critical'), isFalse);
      expect(results.any((r) => r.severity == 'warning'), isFalse);
    });

    test('liste vide retourne un resultat ok', () {
      final results = SupplyChainDefense.auditPackageList([]);
      expect(results, hasLength(1));
      expect(results.first.severity, equals('ok'));
    });
  });

  // =========================================================
  // auditPubspecLock (avec fichier temporaire)
  // =========================================================
  group('SupplyChainDefense.auditPubspecLock', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('test_supply_chain_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('retourne critical si le fichier n existe pas', () async {
      final results = await SupplyChainDefense.auditPubspecLock(
        '${tempDir.path}/nonexistent.lock',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, equals('critical'));
    });

    test('parse un pubspec.lock minimal et retourne ok', () async {
      final lockFile = File('${tempDir.path}/pubspec.lock');
      await lockFile.writeAsString('''
# Generated by pub
packages:
  crypto:
    dependency: "direct main"
    description:
      name: crypto
      sha256: "1234567890abcdef"
      url: "https://pub.dartlang.org"
    source: hosted
    version: "3.0.7"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      final results = await SupplyChainDefense.auditPubspecLock(lockFile.path);
      // crypto est un package de confiance — pas de critical
      expect(results.any((r) => r.severity == 'critical'), isFalse);
    });

    test('detecte un package typosquatte dans le fichier', () async {
      final lockFile = File('${tempDir.path}/pubspec.lock');
      await lockFile.writeAsString('''
# Generated by pub
packages:
  cripto:
    dependency: "direct main"
    description:
      name: cripto
      url: "https://pub.dartlang.org"
    source: hosted
    version: "1.0.0"
''');

      final results = await SupplyChainDefense.auditPubspecLock(lockFile.path);
      expect(results.any((r) => r.severity == 'critical'), isTrue);
    });
  });
}
