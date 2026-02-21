import 'dart:io';

/// Gestionnaire de profils sandbox pour ChillApp.
///
/// Gere les profils AppArmor (Linux) et les entitlements macOS.
/// Permet de deployer, verifier et valider les configurations
/// de confinement de l'application.
class SandboxDeployer {
  SandboxDeployer._();

  /// Profil AppArmor pour ChillApp (Linux).
  static const String appArmorProfile = '''
# =============================================================
# ChillApp - Profil AppArmor restrictif
# Installer : cp chillapp /etc/apparmor.d/ && apparmor_parser -r /etc/apparmor.d/chillapp
# =============================================================

#include <tunables/global>

profile chillapp /opt/chillapp/chillapp flags=(enforce) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  # --- Reseau ---
  network inet stream,
  network inet6 stream,

  # --- Systeme de fichiers ---
  /opt/chillapp/** r,
  /opt/chillapp/chillapp ix,
  /opt/chillapp/lib/** mr,
  /opt/chillapp/chill-tailscale ix,
  /opt/chillapp/chill-tailscale-* ix,

  # Flutter runtime
  /usr/lib/x86_64-linux-gnu/libflutter_linux_gtk.so mr,
  /usr/lib/x86_64-linux-gnu/libGLESv2.so* mr,
  /usr/lib/x86_64-linux-gnu/libEGL.so* mr,

  # SharedPreferences
  owner @{HOME}/.local/share/chillapp/ rw,
  owner @{HOME}/.local/share/chillapp/** rw,

  # SSH keys (lecture seule sauf chillapp_* pour la rotation)
  owner @{HOME}/.ssh/ r,
  owner @{HOME}/.ssh/id_ed25519.pub r,
  owner @{HOME}/.ssh/id_rsa.pub r,
  owner @{HOME}/.ssh/authorized_keys r,
  owner @{HOME}/.ssh/chillapp_* rw,

  # Tmp
  /tmp/chill-sec-*/ rw,
  /tmp/chill-sec-*/** rw,

  # GPU
  /dev/dri/ r,
  /dev/dri/** rw,
  /sys/devices/pci**/drm/ r,
  /proc/sys/kernel/random/uuid r,

  # --- INTERDICTIONS ---
  deny /etc/shadow r,
  deny /etc/gshadow r,
  deny /etc/sudoers rw,
  deny /etc/sudoers.d/** rw,
  deny /dev/video* rw,
  deny /dev/snd/** rw,
  deny /usr/bin/su x,
  deny /usr/bin/sudo x,
  deny /usr/bin/pkexec x,
  deny ptrace,
}
''';

  /// Entitlements macOS pour ChillApp.
  static const String macOSEntitlements = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.network.server</key>
  <false/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  <key>com.apple.security.device.camera</key>
  <false/>
  <key>com.apple.security.device.microphone</key>
  <false/>
  <key>com.apple.security.personal-information.addressbook</key>
  <false/>
  <key>com.apple.security.personal-information.calendars</key>
  <false/>
  <key>com.apple.security.personal-information.location</key>
  <false/>
  <key>com.apple.security.cs.allow-jit</key>
  <false/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <false/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <false/>
</dict>
</plist>
''';

  /// Deploie le profil AppArmor sur Linux.
  ///
  /// Necessite les privileges root (via pkexec).
  /// Retourne true si le deploiement a reussi, false sinon.
  static Future<bool> deployAppArmorProfile() async {
    if (!Platform.isLinux) return false;

    // Verifie qu'AppArmor est active
    final check = await Process.run('cat', [
      '/sys/module/apparmor/parameters/enabled',
    ]);
    if (check.exitCode != 0 || check.stdout.toString().trim() != 'Y') {
      return false;
    }

    final tempDir = await Directory.systemTemp.createTemp('chill-aa-');
    final profileFile = File('${tempDir.path}/chillapp');
    await profileFile.writeAsString(appArmorProfile);

    try {
      final result = await Process.run('pkexec', [
        'bash',
        '-c',
        'cp "${profileFile.path}" /etc/apparmor.d/chillapp && '
            'apparmor_parser -r /etc/apparmor.d/chillapp',
      ]);
      return result.exitCode == 0;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Verifie si le profil AppArmor est charge.
  static Future<bool> isAppArmorProfileLoaded() async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('cat', [
        '/sys/kernel/security/apparmor/profiles',
      ]);
      return result.stdout.toString().contains('chillapp');
    } catch (_) {
      return false;
    }
  }

  /// Valide le contenu du profil AppArmor.
  ///
  /// Retourne une liste de problemes trouves (vide = valide).
  static List<String> validateAppArmorProfile(String profile) {
    final issues = <String>[];

    if (!profile.contains('profile chillapp')) {
      issues.add('Missing profile declaration');
    }
    if (!profile.contains('deny /etc/shadow')) {
      issues.add('Missing shadow file deny rule');
    }
    if (!profile.contains('deny ptrace')) {
      issues.add('Missing ptrace deny rule');
    }
    if (!profile.contains('network inet stream')) {
      issues.add('Missing network rule');
    }
    if (!profile.contains('#include <abstractions/base>')) {
      issues.add('Missing base abstractions');
    }

    return issues;
  }

  /// Valide le contenu des entitlements macOS.
  ///
  /// Retourne une liste de problemes trouves (vide = valide).
  static List<String> validateMacOSEntitlements(String entitlements) {
    final issues = <String>[];

    if (!entitlements.contains('com.apple.security.app-sandbox')) {
      issues.add('Missing app-sandbox entitlement');
    }
    if (!entitlements.contains('com.apple.security.network.client')) {
      issues.add('Missing network.client entitlement');
    }
    // La camera et le micro doivent etre desactives
    if (entitlements
            .contains('<key>com.apple.security.device.camera</key>') &&
        !_entitlementIsFalse(
            entitlements, 'com.apple.security.device.camera')) {
      issues.add('Camera should be disabled');
    }
    if (entitlements
            .contains('<key>com.apple.security.device.microphone</key>') &&
        !_entitlementIsFalse(
            entitlements, 'com.apple.security.device.microphone')) {
      issues.add('Microphone should be disabled');
    }

    return issues;
  }

  /// Verifie si une cle d'entitlement est suivie de `&lt;false/&gt;`.
  static bool _entitlementIsFalse(String content, String key) {
    final keyIndex = content.indexOf('<key>$key</key>');
    if (keyIndex == -1) return false;
    // Longueur de "<key>" + key + "</key>" = 5 + key.length + 6 = 11 + key.length
    final afterKey = content.substring(keyIndex + key.length + 11);
    final trimmed = afterKey.trimLeft();
    return trimmed.startsWith('<false/>');
  }
}
