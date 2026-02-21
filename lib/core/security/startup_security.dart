// =============================================================
// FIX-010/011 : Vérification de sécurité au démarrage
// GAP-010 : Anti-DLL Hijacking Windows
// GAP-011 : Anti-LD_PRELOAD Linux / DYLD_INSERT_LIBRARIES macOS
// GAP-023 : Anti-debugging desktop
// GAP-014 : Détection WebSocket anti-Frida
// Fichier : lib/core/security/startup_security.dart
// =============================================================
//
// PROBLÈME : L'app démarrait sans vérifier si l'environnement
// d'exécution était compromis (injection de lib, debugger attaché,
// outils d'instrumentation comme Frida).
//
// SOLUTION : Effectuer des vérifications au démarrage avant tout
// code applicatif. En mode release, quitter si menace critique.
// =============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';

/// Vérificateur de sécurité au démarrage.
/// Détecte les tentatives d'injection de librairie et de debugging.
///
/// Utilisation dans main() :
/// ```dart
/// final report = await StartupSecurityChecker.runAllChecks();
/// // En release, exit(1) est appelé automatiquement si menace critique.
/// ```
class StartupSecurityChecker {
  // Empêche l'instanciation — toutes les méthodes sont statiques.
  StartupSecurityChecker._();

  /// Exécute toutes les vérifications de sécurité au démarrage.
  ///
  /// Ordre d'exécution :
  /// 1. Injection de librairie (LD_PRELOAD / DYLD_INSERT_LIBRARIES)
  /// 2. Détection de debugger attaché
  /// 3. Scan des ports Frida (en release uniquement)
  ///
  /// En mode release, quitte l'application avec exit(1) si une
  /// menace critique est détectée.
  static Future<StartupSecurityReport> runAllChecks() async {
    final report = StartupSecurityReport();

    // 1. Vérifier les variables d'environnement d'injection de librairie
    report.libraryInjection = _checkLibraryInjection();

    // 2. Vérifier si un debugger est attaché au processus courant
    report.debuggerAttached = await _checkDebugger();

    // 3. Scanner les ports Frida (27042-27044) — uniquement en production
    //    En debug, Frida peut être utilisé légitimement par les développeurs
    if (!kDebugMode) {
      report.fridaDetected = await _scanFridaPorts();
    }

    // En release, bloquer immédiatement si menace critique détectée
    if (!kDebugMode && report.hasCriticalThreat) {
      stderr.writeln('[SECURITY] Menace critique détectée. Arrêt forcé.');
      exit(1);
    }

    return report;
  }

  // ===========================================================
  // Vérification 1 : Injection de librairie
  // ===========================================================

  /// Vérifie les variables d'environnement d'injection de librairie.
  ///
  /// - Linux   : LD_PRELOAD permet d'injecter une .so avant les libs système
  /// - macOS   : DYLD_INSERT_LIBRARIES a le même effet
  /// - Windows : détection DLL hijacking via signature (non implémenté ici)
  static LibraryInjectionCheck _checkLibraryInjection() {
    if (Platform.isLinux) {
      final ldPreload = Platform.environment['LD_PRELOAD'];
      if (ldPreload != null && ldPreload.isNotEmpty) {
        return LibraryInjectionCheck(
          detected: true,
          variable: 'LD_PRELOAD',
          value: ldPreload,
        );
      }
    }

    if (Platform.isMacOS) {
      final dyld = Platform.environment['DYLD_INSERT_LIBRARIES'];
      if (dyld != null && dyld.isNotEmpty) {
        return LibraryInjectionCheck(
          detected: true,
          variable: 'DYLD_INSERT_LIBRARIES',
          value: dyld,
        );
      }
    }

    // Windows : pas de variable d'environnement standard pour l'injection
    // Le DLL hijacking est une attaque au niveau filesystem — hors scope ici
    return const LibraryInjectionCheck(detected: false);
  }

  // ===========================================================
  // Vérification 2 : Debugger attaché
  // ===========================================================

  /// Vérifie si un debugger externe est attaché au processus.
  ///
  /// - Linux  : lit TracerPid dans /proc/self/status (0 = pas de debugger)
  /// - Windows : cherche des modules de debugging chargés via PowerShell
  /// - macOS  : utilise sysctl pour détecter le flag P_TRACED
  ///
  /// Retourne false en mode debug pour ne pas bloquer le développement.
  static Future<bool> _checkDebugger() async {
    // En mode debug, cette vérification n'a pas de sens
    if (kDebugMode) return false;

    if (Platform.isLinux) {
      try {
        final status = await File('/proc/self/status').readAsString();
        final tracerLine = status
            .split('\n')
            .firstWhere(
              (line) => line.startsWith('TracerPid:'),
              orElse: () => '',
            );
        final tracerPid =
            int.tryParse(tracerLine.replaceAll('TracerPid:', '').trim()) ?? 0;
        return tracerPid != 0;
      } catch (_) {
        // Accès refusé ou /proc non disponible — on considère que c'est safe
        return false;
      }
    }

    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-Command',
          r'(Get-Process -Id $PID).Modules | Where-Object { $_.ModuleName -like "*dbg*" } | Measure-Object | Select-Object -ExpandProperty Count',
        ]);
        final count = int.tryParse(result.stdout.toString().trim()) ?? 0;
        return count > 0;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isMacOS) {
      try {
        // pid est un getter global de dart:io (PID du processus courant)
        final result = await Process.run('sysctl', [
          'kern.proc.pid.$pid',
        ]);
        return result.stdout.toString().contains('P_TRACED');
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  // ===========================================================
  // Vérification 3 : Ports Frida
  // ===========================================================

  /// Scanne les ports typiques utilisés par Frida (27042-27044).
  ///
  /// Frida est un outil d'instrumentation dynamique permettant
  /// d'intercepter et modifier le comportement d'une application.
  /// Sa présence sur ces ports en production est suspecte.
  static Future<bool> _scanFridaPorts() async {
    for (final port in [27042, 27043, 27044]) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 150),
        );
        await socket.close();
        // Un port Frida ouvert = instrumentation active = menace
        return true;
      } catch (_) {
        // Port fermé = Frida absent sur ce port (comportement normal)
      }
    }
    return false;
  }
}

// =============================================================
// Rapport de sécurité au démarrage
// =============================================================

/// Rapport consolidé des vérifications de sécurité au démarrage.
class StartupSecurityReport {
  /// Résultat de la vérification d'injection de librairie.
  LibraryInjectionCheck libraryInjection =
      const LibraryInjectionCheck(detected: false);

  /// Vrai si un debugger externe est attaché au processus.
  bool debuggerAttached = false;

  /// Vrai si un port Frida est ouvert sur localhost.
  bool fridaDetected = false;

  /// Vrai si au moins une menace critique a été détectée.
  ///
  /// Une menace critique justifie l'arrêt immédiat en production.
  /// L'injection de librairie et Frida sont considérés critiques.
  /// Un debugger attaché est un avertissement mais pas critique
  /// (peut être un debugger système légitime).
  bool get hasCriticalThreat => libraryInjection.detected || fridaDetected;

  /// Liste des avertissements de sécurité (menaces non critiques).
  List<String> get warnings {
    final result = <String>[];
    if (debuggerAttached) {
      result.add('Debugger attaché au processus');
    }
    return result;
  }

  /// Liste des informations de sécurité (état des vérifications).
  List<String> get infos {
    final result = <String>[];
    if (!libraryInjection.detected && !debuggerAttached && !fridaDetected) {
      result.add('Environnement propre — aucune menace détectée');
    }
    return result;
  }

  /// Résumé textuel de toutes les vérifications.
  String get summary {
    final issues = <String>[];
    if (libraryInjection.detected) {
      issues.add('Injection librairie: ${libraryInjection.variable}');
    }
    if (debuggerAttached) {
      issues.add('Debugger attaché');
    }
    if (fridaDetected) {
      issues.add('Frida détecté');
    }
    return issues.isEmpty ? 'OK' : issues.join(', ');
  }
}

// =============================================================
// Résultat de la vérification d'injection de librairie
// =============================================================

/// Résultat de la vérification d'injection de librairie.
class LibraryInjectionCheck {
  /// Vrai si une injection a été détectée.
  final bool detected;

  /// Nom de la variable d'environnement incriminée (ex: 'LD_PRELOAD').
  final String? variable;

  /// Valeur de la variable (le chemin de la librairie injectée).
  /// Attention : ne jamais logger cette valeur en clair en production.
  final String? value;

  const LibraryInjectionCheck({
    required this.detected,
    this.variable,
    this.value,
  });
}
