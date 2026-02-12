import 'dart:io';

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
  /// Exécute une commande simple (sans privilèges élevés)
  static Future<CommandResult> run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    return CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString().trim(),
      stderr: result.stderr.toString().trim(),
    );
  }

  /// Exécute une commande PowerShell (Windows)
  static Future<CommandResult> runPowerShell(String command) async {
    return run('powershell', ['-NoProfile', '-Command', command]);
  }

  /// Exécute une commande avec privilèges élevés
  static Future<CommandResult> runElevated(String executable, List<String> args) async {
    if (Platform.isWindows) {
      // Sur Windows : relancer PowerShell en admin
      final command = '$executable ${args.join(' ')}';
      return run('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Process powershell -Verb RunAs -ArgumentList \'-NoProfile -Command "$command"\' -Wait',
      ]);
    } else if (Platform.isLinux) {
      // Sur Linux : utiliser pkexec (boîte de dialogue graphique)
      return run('pkexec', [executable, ...args]);
    } else if (Platform.isMacOS) {
      // Sur Mac : utiliser osascript pour demander le mot de passe admin
      final command = '$executable ${args.join(' ')}';
      return run('osascript', [
        '-e',
        'do shell script "$command" with administrator privileges',
      ]);
    }
    throw UnsupportedError('OS non supporté');
  }
}
