import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/command_runner.dart';
import '../../core/os_detector.dart';

/// Provider pour le thème (true = sombre par défaut)
final themeModeProvider = NotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true; // sombre par défaut
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('darkMode') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', state);
  }
}

/// Provider pour le lancement au démarrage (null = en cours de vérification)
final autostartProvider =
    NotifierProvider<AutostartNotifier, bool?>(AutostartNotifier.new);

class AutostartNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    _check();
    return null;
  }

  Future<void> _check() async {
    state = await _isEnabled();
  }

  Future<bool> _isEnabled() async {
    try {
      switch (OsDetector.currentOS) {
        case SupportedOS.windows:
          final result = await CommandRunner.runPowerShell(
            'Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" '
            '-Name "Chill" -ErrorAction SilentlyContinue | '
            'Select-Object -ExpandProperty Chill',
          );
          return result.success && result.stdout.trim().isNotEmpty;
        case SupportedOS.linux:
          final home = Platform.environment['HOME'] ?? '';
          return File('$home/.config/autostart/chillapp.desktop').existsSync();
        case SupportedOS.macos:
          final home = Platform.environment['HOME'] ?? '';
          return File('$home/Library/LaunchAgents/com.chill.chillapp.plist')
              .existsSync();
      }
    } catch (e) {
      debugPrint('[Autostart] Check error: $e');
      return false;
    }
  }

  Future<void> toggle() async {
    final current = state ?? false;
    if (current) {
      await _disable();
    } else {
      await _enable();
    }
    await _check();
  }

  Future<void> _enable() async {
    final exePath = Platform.resolvedExecutable;
    switch (OsDetector.currentOS) {
      case SupportedOS.windows:
        await CommandRunner.runPowerShell(
          'New-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" '
          '-Name "Chill" -Value "\\"$exePath\\"" -PropertyType String -Force',
        );
        break;
      case SupportedOS.linux:
        final home = Platform.environment['HOME'] ?? '';
        final dir = Directory('$home/.config/autostart');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        File('${dir.path}/chillapp.desktop').writeAsStringSync(
          '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Chill\n'
          'Exec=$exePath\n'
          'X-GNOME-Autostart-enabled=true\n'
          'Comment=Chill configuration hub\n',
        );
        break;
      case SupportedOS.macos:
        final home = Platform.environment['HOME'] ?? '';
        File('$home/Library/LaunchAgents/com.chill.chillapp.plist')
            .writeAsStringSync(
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
          '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
          '<plist version="1.0">\n'
          '<dict>\n'
          '  <key>Label</key>\n'
          '  <string>com.chill.chillapp</string>\n'
          '  <key>ProgramArguments</key>\n'
          '  <array>\n'
          '    <string>$exePath</string>\n'
          '  </array>\n'
          '  <key>RunAtLoad</key>\n'
          '  <true/>\n'
          '</dict>\n'
          '</plist>\n',
        );
        break;
    }
  }

  Future<void> _disable() async {
    switch (OsDetector.currentOS) {
      case SupportedOS.windows:
        await CommandRunner.runPowerShell(
          'Remove-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" '
          '-Name "Chill" -ErrorAction SilentlyContinue',
        );
        break;
      case SupportedOS.linux:
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/.config/autostart/chillapp.desktop');
        if (file.existsSync()) file.deleteSync();
        break;
      case SupportedOS.macos:
        final home = Platform.environment['HOME'] ?? '';
        final file =
            File('$home/Library/LaunchAgents/com.chill.chillapp.plist');
        if (file.existsSync()) file.deleteSync();
        break;
    }
  }
}
