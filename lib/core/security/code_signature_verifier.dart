// =============================================================
// FIX-018 : Packaging securise (MSIX/Snap/DMG notarise)
// FIX-019 : Signature de code multi-OS
// GAP-018 : Packaging securise absent
// GAP-019 : Signature de code absente multi-OS
// Cible   : lib/core/security/code_signature_verifier.dart
// =============================================================
//
// PROBLEME : L'app est distribuee sans sandbox packaging ni
// signature. N'importe qui peut remplacer le binaire ou injecter
// du code malveillant dans le package.
//
// SOLUTION :
// 1. Verification de signature au runtime par OS
// 2. Templates de configuration de packaging (constantes)
// =============================================================

import 'dart:io';

/// Resultat detaille de la verification de signature.
class SignatureResult {
  /// Statut de la verification.
  final SignatureStatus status;

  /// Message de detail (erreur, raison, info).
  final String details;

  const SignatureResult({
    required this.status,
    this.details = '',
  });

  /// Retourne true si la signature est valide.
  bool get isValid => status == SignatureStatus.valid;

  @override
  String toString() => 'SignatureResult(${status.name}: $details)';
}

/// Statut possible d'une verification de signature.
enum SignatureStatus {
  /// Signature valide et verifiee.
  valid,

  /// Signature presente mais invalide.
  invalid,

  /// Binaire non signe.
  unsigned,

  /// Erreur lors de la verification (outil absent, etc.).
  error,
}

/// Verificateur de signature de code au runtime.
///
/// Permet de s'assurer que le binaire n'a pas ete altere
/// ou remplace par une version malveillante.
class CodeSignatureVerifier {
  /// Verifie que l'executable courant est correctement signe.
  ///
  /// Utilise les outils natifs de chaque OS :
  /// - Windows : Authenticode via PowerShell `Get-AuthenticodeSignature`
  /// - macOS   : `codesign --verify --deep --strict`
  /// - Linux   : GPG via `gpg --verify`
  ///
  /// Retourne un [SignatureResult] avec le statut et les details.
  static Future<SignatureResult> verifyCurrentBinary() async {
    if (Platform.isWindows) return _verifyWindows();
    if (Platform.isMacOS) return _verifyMacOS();
    if (Platform.isLinux) return _verifyLinux();
    return const SignatureResult(
      status: SignatureStatus.error,
      details: 'Plateforme non supportee',
    );
  }

  // -----------------------------------------------------------
  // Implementations par OS
  // -----------------------------------------------------------

  /// Windows : verification Authenticode via PowerShell.
  static Future<SignatureResult> _verifyWindows() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final result = await Process.run('powershell', [
        '-NonInteractive',
        '-Command',
        '(Get-AuthenticodeSignature "$exePath").Status',
      ]);

      if (result.exitCode != 0) {
        return SignatureResult(
          status: SignatureStatus.error,
          details: result.stderr.toString().trim(),
        );
      }

      final output = result.stdout.toString().trim();
      switch (output) {
        case 'Valid':
          return const SignatureResult(status: SignatureStatus.valid);
        case 'NotSigned':
          return const SignatureResult(
            status: SignatureStatus.unsigned,
            details: 'Binaire non signe Authenticode',
          );
        default:
          return SignatureResult(
            status: SignatureStatus.invalid,
            details: 'Statut Authenticode : $output',
          );
      }
    } catch (e) {
      return SignatureResult(
        status: SignatureStatus.error,
        details: 'Erreur verification Windows : $e',
      );
    }
  }

  /// macOS : verification codesign.
  static Future<SignatureResult> _verifyMacOS() async {
    try {
      final exePath = Platform.resolvedExecutable;

      // Remonter au bundle .app si applicable
      final appBundle = exePath.contains('.app/')
          ? exePath.substring(0, exePath.indexOf('.app/') + 4)
          : exePath;

      final result = await Process.run('codesign', [
        '--verify',
        '--deep',
        '--strict',
        appBundle,
      ]);

      if (result.exitCode == 0) {
        return const SignatureResult(status: SignatureStatus.valid);
      }

      final stderr = result.stderr.toString().trim();
      if (stderr.contains('not signed') || stderr.contains('no signature')) {
        return SignatureResult(
          status: SignatureStatus.unsigned,
          details: stderr,
        );
      }

      return SignatureResult(
        status: SignatureStatus.invalid,
        details: stderr,
      );
    } catch (e) {
      return SignatureResult(
        status: SignatureStatus.error,
        details: 'Erreur verification macOS : $e',
      );
    }
  }

  /// Linux : verification GPG du binaire.
  static Future<SignatureResult> _verifyLinux() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final sigPath = '$exePath.sig';

      // Verifier que le fichier de signature existe
      if (!await File(sigPath).exists()) {
        return SignatureResult(
          status: SignatureStatus.unsigned,
          details: 'Fichier de signature absent : $sigPath',
        );
      }

      final result = await Process.run('gpg', [
        '--verify',
        sigPath,
        exePath,
      ]);

      if (result.exitCode == 0) {
        return const SignatureResult(status: SignatureStatus.valid);
      }

      return SignatureResult(
        status: SignatureStatus.invalid,
        details: result.stderr.toString().trim(),
      );
    } catch (e) {
      return SignatureResult(
        status: SignatureStatus.error,
        details: 'Erreur verification Linux : $e',
      );
    }
  }
}

// =============================================================
// TEMPLATES DE PACKAGING (FIX-018)
// Constantes pures — aucun fichier n'est cree au runtime.
// =============================================================

/// Configuration MSIX pour Windows (a ajouter dans pubspec.yaml).
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

/// Script de build Windows (MSIX + signature Authenticode).
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

/// Configuration Snap pour Linux (sandbox AppArmor strict).
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

/// Script de build macOS (DMG + signature Developer ID + notarisation).
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
