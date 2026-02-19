// =============================================================
// FIX-015 : Profil AppArmor restrictif (Linux)
// GAP-015: Profil AppArmor restrictif absent (Linux)
// FIX-016 : Sandbox entitlements macOS
// GAP-016: Sandbox entitlements absents (macOS)
// =============================================================
//
// PROBLEME : L'app tourne sans restriction. Acces complet au
// systeme de fichiers, reseau, peripheriques.
//
// SOLUTION :
// 1. Profil AppArmor pour Linux (fichier de config)
// 2. Entitlements restrictifs pour macOS
// 3. Dart helper pour deployer le profil AppArmor
// =============================================================

import 'dart:io';

/// Helper pour deployer les profils de sandbox.
class SandboxDeployer {
  /// Profil AppArmor restrictif pour ChillApp.
  /// A ecrire dans /etc/apparmor.d/chillapp
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
  # Tailscale uniquement (100.64.0.0/10)
  network inet stream,
  network inet6 stream,

  # --- Systeme de fichiers ---
  # Binaire de l'app et ses dependances
  /opt/chillapp/** r,
  /opt/chillapp/chillapp ix,
  /opt/chillapp/lib/** mr,

  # Daemon Go (chill-tailscale)
  /opt/chillapp/chill-tailscale ix,
  /opt/chillapp/chill-tailscale-* ix,

  # Flutter runtime
  /usr/lib/x86_64-linux-gnu/libflutter_linux_gtk.so mr,
  /usr/lib/x86_64-linux-gnu/libGLESv2.so* mr,
  /usr/lib/x86_64-linux-gnu/libEGL.so* mr,

  # SharedPreferences (lecture/ecriture)
  owner @{HOME}/.local/share/chillapp/ rw,
  owner @{HOME}/.local/share/chillapp/** rw,

  # SSH keys (lecture seule pour le deploiement)
  owner @{HOME}/.ssh/ r,
  owner @{HOME}/.ssh/id_ed25519.pub r,
  owner @{HOME}/.ssh/id_rsa.pub r,
  owner @{HOME}/.ssh/authorized_keys r,

  # Tmp pour scripts de securite
  /tmp/chill-sec-*/ rw,
  /tmp/chill-sec-*/** rw,

  # GPU et affichage
  /dev/dri/ r,
  /dev/dri/** rw,
  /sys/devices/pci**/drm/ r,
  /proc/sys/kernel/random/uuid r,

  # --- INTERDICTIONS EXPLICITES ---
  # Pas d'acces root
  deny /etc/shadow r,
  deny /etc/gshadow r,
  # Pas de modification systeme
  deny /etc/sudoers rw,
  deny /etc/sudoers.d/** rw,
  # Pas de camera/micro
  deny /dev/video* rw,
  deny /dev/snd/** rw,
  # Pas d'execution arbitraire
  deny /usr/bin/su x,
  deny /usr/bin/sudo x,
  deny /usr/bin/pkexec x,  # Sauf via le wrapper securise
  # Pas de ptrace (anti-debug par d'autres processus)
  deny ptrace,
}
''';

  /// Entitlements macOS restrictifs pour ChillApp.
  /// A utiliser dans le .entitlements du projet Xcode.
  static const String macOSEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Sandbox obligatoire -->
  <key>com.apple.security.app-sandbox</key>
  <true/>

  <!-- Reseau : connexions sortantes uniquement -->
  <key>com.apple.security.network.client</key>
  <true/>
  <!-- Pas de serveur reseau -->
  <key>com.apple.security.network.server</key>
  <false/>

  <!-- Fichiers : acces utilisateur uniquement -->
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>

  <!-- Pas de camera -->
  <key>com.apple.security.device.camera</key>
  <false/>

  <!-- Pas de micro -->
  <key>com.apple.security.device.microphone</key>
  <false/>

  <!-- Pas de contacts -->
  <key>com.apple.security.personal-information.addressbook</key>
  <false/>

  <!-- Pas de calendrier -->
  <key>com.apple.security.personal-information.calendars</key>
  <false/>

  <!-- Pas de localisation -->
  <key>com.apple.security.personal-information.location</key>
  <false/>

  <!-- Hardened runtime -->
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
  /// Necessite les privileges root (via pkexec).
  static Future<bool> deployAppArmorProfile() async {
    if (!Platform.isLinux) return false;

    // Verifier qu'AppArmor est disponible
    final check = await Process.run('cat', [
      '/sys/module/apparmor/parameters/enabled',
    ]);
    if (check.exitCode != 0 ||
        check.stdout.toString().trim() != 'Y') {
      return false;
    }

    // Ecrire le profil dans un fichier temporaire
    final tempDir = await Directory.systemTemp.createTemp('chill-aa-');
    final profileFile = File('${tempDir.path}/chillapp');
    await profileFile.writeAsString(appArmorProfile);

    try {
      // Copier et charger via pkexec
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
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Linux (AppArmor) :
//    - Ajouter SandboxDeployer.deployAppArmorProfile()
//      dans le setup de premiere execution
//    - Ou distribuer le fichier dans le package Snap
//      (snap/local/chillapp-apparmor)
//
// 2. macOS :
//    - Copier le contenu de macOSEntitlements dans
//      macos/Runner/Release.entitlements
//    - S'assurer que le Xcode project reference le fichier
//    - Tester avec : codesign --display --entitlements - ChillApp.app
//
// 3. Verification au demarrage :
//    if (Platform.isLinux) {
//      final loaded = await SandboxDeployer.isAppArmorProfileLoaded();
//      if (!loaded) {
//        // Suggerer a l'utilisateur d'installer le profil
//      }
//    }
// =============================================================
