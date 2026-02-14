import 'dart:io';
import 'command_runner.dart';

/// Methodes statiques pour recuperer les infos reseau selon l'OS.
class NetworkInfo {
  /// Valide un nom d'interface réseau (Linux/macOS).
  /// Noms valides : eth0, enp0s3, wlan0, br-lan, veth1234abc, en0, etc.
  /// Max 15 chars (IFNAMSIZ - 1), alphanumériques + . - _
  static bool isValidInterfaceName(String name) {
    return name.isNotEmpty &&
        name.length <= 15 &&
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(name);
  }

  /// Recupere l'IP Ethernet.
  static Future<String?> getEthernetIp() async {
    if (Platform.isWindows) {
      final result = await CommandRunner.runPowerShell(
        "\$a = Get-NetAdapter | Where-Object { "
        "\$_.Status -eq 'Up' -and "
        "\$_.InterfaceDescription -notlike '*Wi-Fi*' -and "
        "\$_.InterfaceDescription -notlike '*Wireless*' -and "
        "\$_.InterfaceDescription -notlike '*Bluetooth*' -and "
        "\$_.InterfaceDescription -notlike '*Virtual*' "
        "} | Select-Object -First 1; "
        "if (\$a) { (Get-NetIPAddress -InterfaceIndex \$a.ifIndex "
        "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress }",
      );
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else if (Platform.isLinux) {
      final adapter = await findEthernetAdapter();
      if (adapter == null) return null;
      if (!isValidInterfaceName(adapter)) return null;
      final result = await CommandRunner.run('bash', [
        '-c',
        "ip -4 addr show $adapter 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else if (Platform.isMacOS) {
      final hwResult = await CommandRunner.run('networksetup', ['-listallhardwareports']);
      final lines = hwResult.stdout.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('Ethernet') || lines[i].contains('Thunderbolt')) {
          if (i + 1 < lines.length) {
            final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
            if (match != null) {
              final r = await CommandRunner.run('ipconfig', ['getifaddr', match.group(1)!]);
              if (r.stdout.isNotEmpty) return r.stdout;
            }
          }
        }
      }
      // Fallback en1
      final en1 = await CommandRunner.run('ipconfig', ['getifaddr', 'en1']);
      return en1.success && en1.stdout.isNotEmpty ? en1.stdout : null;
    }
    return null;
  }

  /// Recupere l'IP WiFi.
  static Future<String?> getWifiIp() async {
    if (Platform.isWindows) {
      final result = await CommandRunner.runPowerShell(
        "\$a = Get-NetAdapter | Where-Object { "
        "\$_.Status -eq 'Up' -and "
        "(\$_.InterfaceDescription -like '*Wi-Fi*' -or "
        "\$_.InterfaceDescription -like '*Wireless*') "
        "} | Select-Object -First 1; "
        "if (\$a) { (Get-NetIPAddress -InterfaceIndex \$a.ifIndex "
        "-AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress }",
      );
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else if (Platform.isLinux) {
      final wifiFind = await CommandRunner.run('bash', [
        '-c',
        'for iface in \$(ls /sys/class/net/); do '
        'if [ -d "/sys/class/net/\$iface/wireless" ]; then '
        'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
        'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
        'fi; done; exit 1',
      ]);
      if (!wifiFind.success || wifiFind.stdout.isEmpty) return null;
      final wifiIface = wifiFind.stdout.trim();
      if (!isValidInterfaceName(wifiIface)) return null;
      final result = await CommandRunner.run('bash', [
        '-c',
        "ip -4 addr show $wifiIface 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1",
      ]);
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else if (Platform.isMacOS) {
      final hwResult = await CommandRunner.run('networksetup', ['-listallhardwareports']);
      final lines = hwResult.stdout.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('Wi-Fi')) {
          if (i + 1 < lines.length) {
            final match = RegExp(r'Device:\s*(en\d+)').firstMatch(lines[i + 1]);
            if (match != null) {
              final r = await CommandRunner.run('ipconfig', ['getifaddr', match.group(1)!]);
              if (r.stdout.isNotEmpty) return r.stdout;
            }
          }
        }
      }
      // Fallback en0
      final en0 = await CommandRunner.run('ipconfig', ['getifaddr', 'en0']);
      return en0.success && en0.stdout.isNotEmpty ? en0.stdout : null;
    }
    return null;
  }

  /// Recupere le nom d'utilisateur SSH (celui à utiliser pour se connecter).
  static Future<String?> getUsername() async {
    if (Platform.isWindows) {
      final result = await CommandRunner.runPowerShell("\$env:USERNAME");
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else {
      final result = await CommandRunner.run('whoami', []);
      return result.stdout.isNotEmpty ? result.stdout : null;
    }
  }

  /// Recupere le nom de la machine.
  static Future<String?> getHostname() async {
    if (Platform.isWindows) {
      final result = await CommandRunner.runPowerShell("\$env:COMPUTERNAME");
      return result.stdout.isNotEmpty ? result.stdout : null;
    } else {
      final result = await CommandRunner.run('hostname', []);
      return result.stdout.isNotEmpty ? result.stdout : null;
    }
  }

  /// Recupere l'adresse MAC d'une interface (Linux seulement).
  static Future<String?> getMacAddress(String adapter) async {
    if (!Platform.isLinux) return null;
    if (!isValidInterfaceName(adapter)) return null;
    final result = await CommandRunner.run('cat', ['/sys/class/net/$adapter/address']);
    return result.stdout.isNotEmpty ? result.stdout : null;
  }

  /// Trouve l'interface Ethernet active (Linux seulement).
  static Future<String?> findEthernetAdapter() async {
    if (!Platform.isLinux) return null;
    final result = await CommandRunner.run('bash', [
      '-c',
      'FALLBACK=""; '
      'for iface in \$(ls /sys/class/net/); do '
      'if [ "\$iface" = "lo" ]; then continue; fi; '
      'if [ -d "/sys/class/net/\$iface/wireless" ]; then continue; fi; '
      'if [ -e "/sys/class/net/\$iface/device" ]; then '
      'carrier=\$(cat /sys/class/net/\$iface/carrier 2>/dev/null || echo "0"); '
      'if [ "\$carrier" = "1" ]; then echo "\$iface"; exit 0; fi; '
      'FALLBACK="\$iface"; '
      'fi; '
      'done; '
      'if [ -n "\$FALLBACK" ]; then echo "\$FALLBACK"; exit 0; fi; '
      'exit 1',
    ]);
    return result.success && result.stdout.isNotEmpty ? result.stdout.trim() : null;
  }
}
