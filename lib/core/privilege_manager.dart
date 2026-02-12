import 'dart:io';
import 'command_runner.dart';

/// Gère la vérification et l'élévation des privilèges
class PrivilegeManager {
  /// Vérifie si l'app a les droits admin
  static Future<bool> hasElevatedPrivileges() async {
    if (Platform.isWindows) {
      final result = await CommandRunner.run('net', ['session']);
      return result.success;
    } else {
      // Sur Linux/Mac, on vérifie si on est root
      final result = await CommandRunner.run('id', ['-u']);
      return result.stdout == '0';
    }
  }
}
