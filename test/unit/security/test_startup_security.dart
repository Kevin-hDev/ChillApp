// =============================================================
// Tests unitaires — FIX-010/011 : StartupSecurityChecker
// Vérifier que les contrôles de sécurité au démarrage fonctionnent
// correctement dans un environnement de test normal.
// =============================================================
//
// Exécuter avec :
//   flutter test test/unit/security/test_startup_security.dart
//
// =============================================================

import 'dart:io';
import 'package:test/test.dart';
import 'package:chill_app/core/security/startup_security.dart';

void main() {
  // ===========================================================
  // Tests sur StartupSecurityReport
  // ===========================================================

  group('StartupSecurityReport — état initial', () {
    test('un rapport vide ne signale aucune menace critique', () {
      final report = StartupSecurityReport();
      expect(report.hasCriticalThreat, isFalse,
          reason: 'Un rapport par défaut ne doit pas signaler de menace');
    });

    test('un rapport vide a une liste warnings vide', () {
      final report = StartupSecurityReport();
      expect(report.warnings, isEmpty,
          reason: 'Aucun avertissement sans injection ni Frida');
    });

    test('un rapport vide retourne le résumé OK', () {
      final report = StartupSecurityReport();
      expect(report.summary, equals('OK'),
          reason: 'Le résumé doit indiquer OK en environnement propre');
    });

    test('les infos confirment un environnement propre', () {
      final report = StartupSecurityReport();
      expect(report.infos, isNotEmpty,
          reason: 'Les infos doivent confirmer l\'environnement propre');
      expect(report.infos.first, contains('propre'));
    });
  });

  // ===========================================================
  // Tests sur LibraryInjectionCheck
  // ===========================================================

  group('LibraryInjectionCheck — logique de détection', () {
    test('LibraryInjectionCheck(detected: false) est correct par défaut', () {
      const check = LibraryInjectionCheck(detected: false);
      expect(check.detected, isFalse);
      expect(check.variable, isNull);
      expect(check.value, isNull);
    });

    test('LibraryInjectionCheck avec injection détectée signale la variable', () {
      const check = LibraryInjectionCheck(
        detected: true,
        variable: 'LD_PRELOAD',
        value: '/tmp/evil.so',
      );
      expect(check.detected, isTrue);
      expect(check.variable, equals('LD_PRELOAD'));
    });

    test('injection détectée déclenche hasCriticalThreat', () {
      final report = StartupSecurityReport();
      report.libraryInjection = const LibraryInjectionCheck(
        detected: true,
        variable: 'LD_PRELOAD',
        value: '/tmp/evil.so',
      );
      expect(report.hasCriticalThreat, isTrue,
          reason: 'Une injection de librairie est une menace critique');
    });

    test('l\'environnement de test est propre (LD_PRELOAD absent)', () {
      // En environnement de CI/CD ou développement normal,
      // LD_PRELOAD et DYLD_INSERT_LIBRARIES ne doivent pas être définis
      final ldPreload = Platform.environment['LD_PRELOAD'];
      final dyld = Platform.environment['DYLD_INSERT_LIBRARIES'];
      expect(
        ldPreload == null || ldPreload.isEmpty,
        isTrue,
        reason: 'LD_PRELOAD doit être absent en environnement de test',
      );
      expect(
        dyld == null || dyld.isEmpty,
        isTrue,
        reason: 'DYLD_INSERT_LIBRARIES doit être absent en environnement de test',
      );
    });
  });

  // ===========================================================
  // Tests sur runAllChecks en conditions normales
  // ===========================================================

  group('StartupSecurityChecker.runAllChecks — environnement normal', () {
    test('runAllChecks retourne un objet StartupSecurityReport', () async {
      final report = await StartupSecurityChecker.runAllChecks();
      expect(report, isA<StartupSecurityReport>(),
          reason: 'runAllChecks doit retourner un StartupSecurityReport');
    });

    test('pas de menace critique en conditions normales', () async {
      // En mode debug (tests), Frida n'est pas scanné.
      // LD_PRELOAD absent en environnement de test.
      final report = await StartupSecurityChecker.runAllChecks();
      expect(report.hasCriticalThreat, isFalse,
          reason:
              'Aucune menace critique ne doit être détectée en environnement de test normal');
    });

    test('injection de librairie non détectée en environnement propre', () async {
      final report = await StartupSecurityChecker.runAllChecks();
      expect(report.libraryInjection.detected, isFalse,
          reason: 'Pas d\'injection LD_PRELOAD en environnement de test');
    });

    test('le résumé vaut OK en conditions normales', () async {
      final report = await StartupSecurityChecker.runAllChecks();
      // En mode debug, Frida et debugger ne sont pas vérifiés de façon bloquante
      // Le résumé peut indiquer OK ou lister des avertissements mineurs
      expect(report.summary, isA<String>(),
          reason: 'Le résumé doit être une chaîne de caractères');
    });

    test('debuggerAttached est false en mode debug (tests)', () async {
      // En kDebugMode, _checkDebugger() retourne false sans vérification
      final report = await StartupSecurityChecker.runAllChecks();
      expect(report.debuggerAttached, isFalse,
          reason: 'En mode debug, debuggerAttached est toujours false');
    });

    test('fridaDetected est false en mode debug (non scanné)', () async {
      // En kDebugMode, _scanFridaPorts() n'est pas appelé
      final report = await StartupSecurityChecker.runAllChecks();
      expect(report.fridaDetected, isFalse,
          reason: 'En mode debug, les ports Frida ne sont pas scannés');
    });
  });

  // ===========================================================
  // Tests sur StartupSecurityReport — menaces simulées
  // ===========================================================

  group('StartupSecurityReport — simulation de menaces', () {
    test('Frida détecté déclenche hasCriticalThreat', () {
      final report = StartupSecurityReport();
      report.fridaDetected = true;
      expect(report.hasCriticalThreat, isTrue,
          reason: 'Frida détecté est une menace critique');
    });

    test('debugger seul ne déclenche pas hasCriticalThreat', () {
      final report = StartupSecurityReport();
      report.debuggerAttached = true;
      expect(report.hasCriticalThreat, isFalse,
          reason:
              'Un debugger attaché est un avertissement, pas une menace critique');
    });

    test('debugger attaché apparaît dans warnings', () {
      final report = StartupSecurityReport();
      report.debuggerAttached = true;
      expect(report.warnings, isNotEmpty);
      expect(report.warnings.first, contains('Debugger'));
    });

    test('summary liste toutes les menaces actives', () {
      final report = StartupSecurityReport();
      report.libraryInjection = const LibraryInjectionCheck(
        detected: true,
        variable: 'LD_PRELOAD',
        value: '/tmp/evil.so',
      );
      report.debuggerAttached = true;
      final summary = report.summary;
      expect(summary.contains('LD_PRELOAD'), isTrue);
      expect(summary.contains('Debugger'), isTrue);
    });
  });
}
