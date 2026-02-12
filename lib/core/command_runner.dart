import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Résultat d'une commande exécutée
class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;
}

/// Exécute des commandes système selon l'OS
class CommandRunner {
  /// Timeout par défaut pour les commandes (120 secondes)
  static const _defaultTimeout = Duration(seconds: 120);

  /// Exécute une commande simple (sans privilèges élevés)
  // NOTE: Process.run().timeout() does not kill the underlying process on timeout.
  // The process continues running in the background. This is a known Dart limitation.
  // For long-running commands (pkexec, apt), orphan processes may accumulate.
  // A future improvement would be to use Process.start() with explicit kill on timeout.
  static Future<CommandResult> run(
    String executable,
    List<String> args, {
    Duration? timeout,
  }) async {
    try {
      final result = await Process.run(
        executable,
        args,
      ).timeout(timeout ?? _defaultTimeout);
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } on TimeoutException {
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: 'La commande a dépassé le délai d\'attente.',
      );
    } on ProcessException catch (e) {
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.message,
      );
    }
  }

  /// Exécute une commande PowerShell (Windows)
  static Future<CommandResult> runPowerShell(
    String command, {
    Duration? timeout,
  }) async {
    return run('powershell', ['-NoProfile', '-Command', command], timeout: timeout);
  }

  /// Échappement shell POSIX complet — entoure de single quotes
  static String _shellQuote(String arg) {
    // En POSIX shell, tout ce qui est entre single quotes est littéral,
    // sauf les single quotes elles-mêmes qu'on gère avec '\''
    return "'${arg.replaceAll("'", "'\\''")}'";
  }

  /// Échappement PowerShell — entoure de single quotes (pas d'interpolation)
  static String _psQuote(String arg) {
    return "'${arg.replaceAll("'", "''")}'";
  }

  /// Exécute une commande avec privilèges élevés
  static Future<CommandResult> runElevated(String executable, List<String> args) async {
    if (Platform.isWindows) {
      // Sur Windows : écrire un script .ps1 temporaire pour éviter
      // le triple nesting PowerShell et les injections via arguments
      final tempDir = await Directory.systemTemp.createTemp('chill-');
      final tempScript = File('${tempDir.path}\\elevated.ps1');
      try {
        final escapedArgs = args.map((a) => _psQuote(a)).join(' ');
        final scriptContent = '& ${_psQuote(executable)} $escapedArgs\n';
        await tempScript.writeAsString(scriptContent);

        // -File n'interprète PAS le contenu comme du code PowerShell
        final scriptPath = tempScript.path;
        return run('powershell', [
          '-NoProfile',
          '-Command',
          'Start-Process powershell -Verb RunAs -ArgumentList '
              '@("-NoProfile","-ExecutionPolicy","Bypass","-File","$scriptPath") -Wait',
        ]);
      } finally {
        try { await tempDir.delete(recursive: true); } catch (e) { debugPrint('[CommandRunner] Cleanup error: $e'); }
      }
    } else if (Platform.isLinux) {
      // Sur Linux : utiliser pkexec (boîte de dialogue graphique)
      // Les args sont passés comme liste séparée, pas besoin d'échapper
      return run('pkexec', [executable, ...args]);
    } else if (Platform.isMacOS) {
      // Sur Mac : écrire un script temporaire pour éviter l'injection
      // via backticks, $(), newlines dans les arguments osascript
      final tempDir = await Directory.systemTemp.createTemp('chill-');
      final tempScript = File('${tempDir.path}/elevated.sh');
      try {
        final scriptContent = '#!/bin/bash\n'
            'exec ${_shellQuote(executable)} ${args.map(_shellQuote).join(' ')}\n';
        await tempScript.writeAsString(scriptContent);
        await Process.run('chmod', ['700', tempScript.path]);

        // Seul le chemin du script est injecté dans osascript
        final escapedPath = tempScript.path
            .replaceAll('\\', '\\\\')
            .replaceAll('"', '\\"');
        return run('osascript', [
          '-e',
          'do shell script "bash \\"$escapedPath\\"" with administrator privileges',
        ]);
      } finally {
        try { await tempDir.delete(recursive: true); } catch (e) { debugPrint('[CommandRunner] Cleanup error: $e'); }
      }
    }
    throw UnsupportedError('OS non supporté');
  }
}
