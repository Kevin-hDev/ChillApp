// =============================================================
// FIX-008 à FIX-011 : Verification de securite au demarrage
// GAP-010: Anti-DLL Hijacking Windows
// GAP-011: Anti-LD_PRELOAD Linux / DYLD_INSERT_LIBRARIES macOS
// GAP-023: Anti-debugging desktop
// GAP-014: Detection WebSocket anti-Frida
// =============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';

/// Verificateur de securite au demarrage.
/// Detecte les tentatives d'injection et de debugging.
/// Appeler dans main() AVANT tout autre code.
class StartupSecurityChecker {
  /// Execute toutes les verifications de securite au demarrage.
  /// Retourne false si une menace est detectee.
  /// En mode release, quitte l'app si une menace critique est trouvee.
  static Future<StartupSecurityReport> runAllChecks() async {
    final report = StartupSecurityReport();

    // 1. Verifier les variables d'environnement d'injection
    report.libraryInjection = _checkLibraryInjection();

    // 2. Verifier si un debugger est attache
    report.debuggerAttached = await _checkDebugger();

    // 3. Scanner les ports Frida
    if (!kDebugMode) {
      report.fridaDetected = await _scanFridaPorts();
    }

    // En release, bloquer si menace critique
    if (!kDebugMode && report.hasCriticalThreat) {
      stderr.writeln('[SECURITY] Menace critique detectee. Arret.');
      exit(1);
    }

    return report;
  }

  /// Verifie les variables d'environnement d'injection de librairie.
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

    // Windows: DLL hijacking est verifie separement via signature
    return const LibraryInjectionCheck(detected: false);
  }

  /// Verifie si un debugger est attache au processus.
  static Future<bool> _checkDebugger() async {
    if (kDebugMode) return false; // Ne pas verifier en debug

    if (Platform.isLinux) {
      try {
        final status = await File('/proc/self/status').readAsString();
        final tracerLine = status
            .split('\n')
            .firstWhere((l) => l.startsWith('TracerPid:'), orElse: () => '');
        final tracerPid =
            int.tryParse(tracerLine.replaceAll('TracerPid:', '').trim()) ?? 0;
        return tracerPid != 0;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-Command',
          '(Get-Process -Id \$PID).Modules | Where-Object { \$_.ModuleName -like "*dbg*" } | Measure-Object | Select-Object -ExpandProperty Count',
        ]);
        return int.tryParse(result.stdout.toString().trim()) != null &&
            int.parse(result.stdout.toString().trim()) > 0;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isMacOS) {
      try {
        final result = await Process.run('sysctl', [
          'kern.proc.pid.${pid}',
        ]);
        return result.stdout.toString().contains('P_TRACED');
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  /// Scanne les ports typiques de Frida (27042-27044).
  static Future<bool> _scanFridaPorts() async {
    for (final port in [27042, 27043, 27044]) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 150),
        );
        await socket.close();
        return true; // Port Frida ouvert
      } catch (_) {
        // Port ferme = pas de Frida sur ce port
      }
    }
    return false;
  }
}

/// Rapport des verifications de securite au demarrage.
class StartupSecurityReport {
  LibraryInjectionCheck libraryInjection =
      const LibraryInjectionCheck(detected: false);
  bool debuggerAttached = false;
  bool fridaDetected = false;

  /// Vrai si une menace critique necessite l'arret.
  bool get hasCriticalThreat =>
      libraryInjection.detected || fridaDetected;

  /// Resume textuel des verifications.
  String get summary {
    final issues = <String>[];
    if (libraryInjection.detected) {
      issues.add('Injection librairie: ${libraryInjection.variable}');
    }
    if (debuggerAttached) issues.add('Debugger attache');
    if (fridaDetected) issues.add('Frida detecte');
    return issues.isEmpty ? 'OK' : issues.join(', ');
  }
}

/// Resultat de la verification d'injection de librairie.
class LibraryInjectionCheck {
  final bool detected;
  final String? variable;
  final String? value;

  const LibraryInjectionCheck({
    required this.detected,
    this.variable,
    this.value,
  });
}
