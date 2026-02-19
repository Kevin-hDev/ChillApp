// =============================================================
// FIX-018 : Packaging securise (MSIX/Snap/DMG notarise)
// GAP-018: Packaging securise absent
// FIX-019 : Signature de code multi-OS
// GAP-019: Signature de code absente multi-OS
// =============================================================
//
// PROBLEME : L'app est distribuee sans sandbox packaging ni
// signature. N'importe qui peut remplacer le binaire ou injecter
// du code malveillant dans le package.
//
// SOLUTION :
// 1. Scripts de build pour packaging securise par OS
// 2. Verification de signature au runtime
// 3. Templates de configuration de packaging
// =============================================================

import 'dart:io';

/// Verificateur de signature de code au runtime.
class CodeSignatureVerifier {
  /// Verifie que l'executable est correctement signe.
  /// Retourne true si la signature est valide.
  static Future<bool> verifyCurrentBinary() async {
    if (Platform.isWindows) return _verifyWindows();
    if (Platform.isMacOS) return _verifyMacOS();
    if (Platform.isLinux) return _verifyLinux();
    return false;
  }

  /// Windows : Authenticode signature.
  static Future<bool> _verifyWindows() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final result = await Process.run('powershell', [
        '-Command',
        'Get-AuthenticodeSignature "${exePath}" | '
            'Select-Object -ExpandProperty Status',
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().trim() == 'Valid';
    } catch (_) {
      return false;
    }
  }

  /// macOS : codesign verification.
  static Future<bool> _verifyMacOS() async {
    try {
      final exePath = Platform.resolvedExecutable;
      // Remonter au bundle .app
      final appBundle = exePath.contains('.app/')
          ? exePath.substring(0, exePath.indexOf('.app/') + 4)
          : exePath;

      final result = await Process.run('codesign', [
        '--verify',
        '--deep',
        '--strict',
        appBundle,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Linux : GPG signature verification.
  static Future<bool> _verifyLinux() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final sigPath = '$exePath.sig';

      // Verifier que le fichier de signature existe
      if (!await File(sigPath).exists()) return false;

      final result = await Process.run('gpg', [
        '--verify',
        sigPath,
        exePath,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

// =============================================================
// TEMPLATES DE PACKAGING
// =============================================================

/// Template de configuration MSIX pour Windows.
/// A ajouter dans pubspec.yaml sous la section msix_config.
const String msixConfig = '''
# === pubspec.yaml (ajouter a la fin) ===
msix_config:
  display_name: ChillApp
  publisher_display_name: Chill
  identity_name: com.chill.chillapp
  msix_version: 1.0.0.0
  logo_path: assets/icon/app_icon.png
  # Certificat de signature (requis pour la distribution)
  # certificate_path: build/certs/chillapp.pfx
  # certificate_password: \$CERT_PASSWORD
  capabilities: internetClient
  # Pas de capabilities dangereuses :
  # PAS de : runFullTrust, allJoynRouter, offlineMaps...
''';

/// Script de build Windows MSIX.
const String windowsBuildScript = r'''
#!/bin/bash
# Build Windows MSIX signe
# Prerequis : flutter pub global activate msix

set -e

echo "=== Build Windows Release (obfusque) ==="
flutter build windows --release --obfuscate --split-debug-info=build/symbols/windows

echo "=== Packaging MSIX ==="
flutter pub run msix:create

echo "=== Signature Authenticode ==="
# Decommenter avec votre certificat :
# signtool sign /f build/certs/chillapp.pfx /p "$CERT_PASSWORD" \
#   /t http://timestamp.digicert.com \
#   build/windows/x64/runner/Release/chillapp.msix

echo "=== Build complete ==="
''';

/// Configuration Snap pour Linux.
const String snapcraftConfig = '''
# snapcraft.yaml
name: chillapp
base: core22
version: '1.0.0'
summary: ChillApp - Connexion SSH securisee via Tailscale
description: |
  Application desktop pour gerer les connexions SSH
  via le reseau Tailscale de maniere securisee.

grade: stable
confinement: strict  # Sandbox AppArmor automatique

apps:
  chillapp:
    command: chillapp
    extensions: [gnome]
    plugs:
      - network        # Connexion Tailscale
      - network-bind   # Listener IPC
      - home           # Acces SSH keys
      - desktop        # Integration desktop
      - desktop-legacy
      - wayland
      - x11
    # PAS de plugs dangereux :
    # PAS de : process-control, system-observe, mount-observe

parts:
  chillapp:
    plugin: nil
    source: .
    override-build: |
      flutter build linux --release --obfuscate --split-debug-info=build/symbols/linux
      cp -r build/linux/x64/release/bundle/* \$SNAPCRAFT_PART_INSTALL/
''';

/// Script de build macOS DMG notarise.
const String macosBuildScript = r'''
#!/bin/bash
# Build macOS DMG notarise
set -e

APP_NAME="ChillApp"
BUNDLE_ID="com.chill.chillapp"

echo "=== Build macOS Release (obfusque) ==="
flutter build macos --release --obfuscate --split-debug-info=build/symbols/macos

echo "=== Signature avec Developer ID ==="
# Decommenter avec votre certificat :
# codesign --deep --force --verify --verbose \
#   --sign "Developer ID Application: Votre Nom (TEAM_ID)" \
#   --options runtime \
#   --entitlements macos/Runner/Release.entitlements \
#   "build/macos/Build/Products/Release/$APP_NAME.app"

echo "=== Creation DMG ==="
hdiutil create -volname "$APP_NAME" \
  -srcfolder "build/macos/Build/Products/Release/$APP_NAME.app" \
  -ov -format UDZO \
  "build/$APP_NAME.dmg"

echo "=== Notarisation ==="
# Decommenter :
# xcrun notarytool submit "build/$APP_NAME.dmg" \
#   --apple-id "$APPLE_ID" \
#   --password "$APP_PASSWORD" \
#   --team-id "$TEAM_ID" \
#   --wait

# xcrun stapler staple "build/$APP_NAME.dmg"

echo "=== Build complete ==="
''';

/// Script de signature GPG pour Linux.
const String linuxSignScript = r'''
#!/bin/bash
# Signature GPG du binaire Linux
set -e

BINARY="build/linux/x64/release/bundle/chillapp"

echo "=== Build Linux Release (obfusque) ==="
flutter build linux --release --obfuscate --split-debug-info=build/symbols/linux

echo "=== Signature GPG ==="
# Decommenter :
# gpg --detach-sign --armor "$BINARY"
# echo "Signature: ${BINARY}.asc"

echo "=== Verification ==="
# gpg --verify "${BINARY}.asc" "$BINARY"

echo "=== Build complete ==="
''';

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Creer les scripts de build :
//    - scripts/build_windows.sh (msixConfig + windowsBuildScript)
//    - scripts/build_linux.sh (linuxSignScript)
//    - scripts/build_macos.sh (macosBuildScript)
//    - snap/snapcraft.yaml (snapcraftConfig)
//
// 2. Verification au demarrage (optionnelle, release uniquement) :
//    if (kReleaseMode) {
//      final signed = await CodeSignatureVerifier.verifyCurrentBinary();
//      if (!signed) {
//        auditLog.log(SecurityAction.signatureVerifyFailed);
//        // Avertir l'utilisateur
//      }
//    }
//
// 3. CI/CD :
//    - Stocker les certificats dans les secrets CI
//    - Executer les scripts de build dans le pipeline
//    - Archiver les symbols pour crash reports
// =============================================================
