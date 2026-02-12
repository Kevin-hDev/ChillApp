import 'dart:io';

enum SupportedOS { windows, linux, macos }

enum LinuxDistro { debian, fedora, arch, unknown }

class OsDetector {
  static SupportedOS get currentOS {
    if (Platform.isWindows) return SupportedOS.windows;
    if (Platform.isLinux) return SupportedOS.linux;
    if (Platform.isMacOS) return SupportedOS.macos;
    throw UnsupportedError('OS non supporté : ${Platform.operatingSystem}');
  }

  /// Détecte la distribution Linux via /etc/os-release
  static Future<LinuxDistro> detectLinuxDistro() async {
    try {
      final file = File('/etc/os-release');
      if (!await file.exists()) return LinuxDistro.unknown;

      final content = await file.readAsString();
      final idMatch = RegExp(r'^ID=(.+)$', multiLine: true).firstMatch(content);
      if (idMatch == null) return LinuxDistro.unknown;

      final id = idMatch.group(1)!.replaceAll('"', '').trim();

      switch (id) {
        case 'ubuntu':
        case 'debian':
        case 'linuxmint':
        case 'pop':
          return LinuxDistro.debian;
        case 'fedora':
        case 'rhel':
        case 'centos':
        case 'rocky':
        case 'alma':
          return LinuxDistro.fedora;
        case 'arch':
        case 'manjaro':
        case 'endeavouros':
          return LinuxDistro.arch;
        default:
          return LinuxDistro.unknown;
      }
    } catch (_) {
      return LinuxDistro.unknown;
    }
  }
}
