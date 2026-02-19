// =============================================================
// FIX-026 : WDAC Policies pour Windows
// GAP-026: WDAC policies Windows absentes
// Cible: nouveau fichier de configuration systeme
// =============================================================
//
// PROBLEME : N'importe quel binaire non signe peut s'executer
// dans le contexte de l'app Windows. Un attaquant peut remplacer
// les DLL ou binaires par des versions malveillantes.
//
// SOLUTION :
// 1. Politique WDAC (Windows Defender Application Control)
//    qui whitelist uniquement les binaires signes de ChillApp
// 2. Script de deploiement de la politique
// 3. Verification Dart au runtime
// =============================================================

import 'dart:io';

/// Deploiement de politique WDAC pour Windows.
class WdacPolicyDeployer {
  /// Template de politique WDAC pour ChillApp.
  /// Whitelist uniquement les binaires signes.
  static const String policyXml = '''
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy">
  <VersionEx>10.0.0.0</VersionEx>
  <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID>
  <Rules>
    <!-- Mode audit d'abord, puis enforce -->
    <Rule>
      <Option>Enabled:Audit Mode</Option>
    </Rule>
    <Rule>
      <Option>Enabled:UMCI</Option>
    </Rule>
    <Rule>
      <Option>Required:Enforce Store Applications</Option>
    </Rule>
  </Rules>

  <EKUs />

  <FileRules>
    <!-- ChillApp executable -->
    <Allow ID="ID_ALLOW_CHILLAPP"
           FriendlyName="ChillApp.exe"
           FileName="chillapp.exe"
           MinimumFileVersion="1.0.0.0" />

    <!-- Daemon Go -->
    <Allow ID="ID_ALLOW_DAEMON"
           FriendlyName="chill-tailscale.exe"
           FileName="chill-tailscale.exe"
           MinimumFileVersion="1.0.0.0" />

    <!-- Flutter runtime DLLs -->
    <Allow ID="ID_ALLOW_FLUTTER"
           FriendlyName="flutter_windows.dll"
           FileName="flutter_windows.dll" />
  </FileRules>

  <Signers>
    <!-- Ajouter le certificat de signature ici -->
    <!-- <Signer ID="ID_SIGNER_CHILLAPP" Name="ChillApp Cert">
      <CertRoot Type="TBS" Value="CERT_HASH_HERE" />
    </Signer> -->
  </Signers>

  <SigningScenarios>
    <SigningScenario Value="131"
                     ID="ID_SIGNINGSCENARIO_CHILLAPP"
                     FriendlyName="ChillApp User Mode">
      <ProductSigners>
        <FileRulesRef>
          <FileRuleRef RuleID="ID_ALLOW_CHILLAPP" />
          <FileRuleRef RuleID="ID_ALLOW_DAEMON" />
          <FileRuleRef RuleID="ID_ALLOW_FLUTTER" />
        </FileRulesRef>
      </ProductSigners>
    </SigningScenario>
  </SigningScenarios>

  <UpdatePolicySigners />
  <CiSigners />
  <HvciOptions>0</HvciOptions>
</SiPolicy>
''';

  /// Script PowerShell pour deployer la politique WDAC.
  static const String deployScript = r'''
# ChillApp - Deploiement politique WDAC
# Executer en tant qu'administrateur

$policyPath = "$env:TEMP\ChillAppWDAC.xml"
$binaryPath = "$env:TEMP\ChillAppWDAC.bin"

# 1. Ecrire la politique XML
# (Le contenu est passe en parametre)

# 2. Convertir en binaire
ConvertFrom-CIPolicy -XmlFilePath $policyPath -BinaryFilePath $binaryPath

# 3. Deployer (mode audit d'abord)
Copy-Item $binaryPath "$env:windir\System32\CodeIntegrity\SIPolicy.p7b" -Force

# 4. Redemarrage necessaire pour activer
Write-Output "WDAC policy deployed. Restart required."
''';

  /// Deploie la politique WDAC en mode audit.
  static Future<bool> deployAuditMode() async {
    if (!Platform.isWindows) return false;

    try {
      // Ecrire la politique XML dans un fichier temporaire
      final tempDir = await Directory.systemTemp.createTemp('chill-wdac-');
      final policyFile = File('${tempDir.path}\\ChillAppWDAC.xml');
      await policyFile.writeAsString(policyXml);

      // Deployer via PowerShell eleve
      final result = await Process.run('powershell', [
        '-Command',
        'Start-Process powershell -Verb RunAs -Wait -ArgumentList '
            '"-Command ConvertFrom-CIPolicy -XmlFilePath '
            '\'${policyFile.path}\' -BinaryFilePath '
            '\'${tempDir.path}\\ChillAppWDAC.bin\'; '
            'Copy-Item \'${tempDir.path}\\ChillAppWDAC.bin\' '
            '\'\$env:windir\\System32\\CodeIntegrity\\SIPolicy.p7b\' -Force"',
      ]);

      // Cleanup
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Verifie si une politique WDAC est active.
  static Future<bool> isWdacActive() async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-CimInstance -ClassName Win32_DeviceGuard '
            '-Namespace root\\Microsoft\\Windows\\DeviceGuard | '
            'Select-Object -ExpandProperty CodeIntegrityPolicyEnforcementStatus',
      ]);
      // 0 = off, 1 = audit, 2 = enforced
      final status = int.tryParse(result.stdout.toString().trim()) ?? 0;
      return status > 0;
    } catch (_) {
      return false;
    }
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Generer la politique WDAC :
//    - Remplacer CERT_HASH_HERE par le hash TBS du certificat
//    - Tester en mode audit d'abord (Enabled:Audit Mode)
//    - Surveiller les event logs pour les blocages
//    - Passer en mode enforce apres validation
//
// 2. Deploiement :
//    - Inclure dans l'installateur MSIX
//    - Ou deployer via le menu Securite de l'app :
//      await WdacPolicyDeployer.deployAuditMode();
//
// 3. Verification au demarrage :
//    if (Platform.isWindows) {
//      final wdacActive = await WdacPolicyDeployer.isWdacActive();
//      // Informer l'utilisateur si WDAC n'est pas actif
//    }
//
// NOTE : WDAC est une fonctionnalite Windows Enterprise/Pro.
// Sur Windows Home, cette fonctionnalite n'est pas disponible.
// =============================================================
