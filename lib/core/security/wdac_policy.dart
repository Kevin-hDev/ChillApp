// =============================================================
// FIX-026 : WDAC Policies pour Windows
// GAP-026 : WDAC policies Windows absentes
// Cible   : lib/core/security/wdac_policy.dart
// =============================================================
//
// PROBLEME : N'importe quel binaire non signe peut s'executer
// dans le contexte de l'app Windows. Un attaquant peut remplacer
// les DLL ou binaires par des versions malveillantes.
//
// SOLUTION :
// 1. Template de politique WDAC (Windows Defender Application Control)
//    qui autorise uniquement les binaires signes de ChillApp
// 2. Script de deploiement PowerShell eleve
// 3. Verification du statut WDAC au runtime
// =============================================================

import 'dart:io';

/// Resultat de validation d'une politique WDAC.
class WdacValidationResult {
  /// La politique est structurellement valide.
  final bool isValid;

  /// Liste des problemes detectes dans la politique.
  final List<String> issues;

  const WdacValidationResult({
    required this.isValid,
    this.issues = const [],
  });
}

/// Deploiement et gestion des politiques WDAC pour Windows.
///
/// WDAC (Windows Defender Application Control) permet de restreindre
/// l'execution aux seuls binaires autorises (whitelist). Cela empeche
/// le chargement de DLL malveillantes ou de binaires remplaces.
///
/// NOTE : WDAC est disponible sur Windows Pro et Enterprise.
/// Sur Windows Home, cette fonctionnalite n'est pas disponible.
class WdacPolicyDeployer {
  // ---------------------------------------------------------
  // Template XML de la politique WDAC
  // ---------------------------------------------------------

  /// Template XML de politique WDAC pour ChillApp.
  ///
  /// Autorise en mode audit :
  /// - chillapp.exe (executable principal)
  /// - chill-tailscale.exe (daemon Go)
  /// - flutter_windows.dll (runtime Flutter)
  ///
  /// Passer en mode enforce apres validation des logs d'audit.
  static const String policyXml = '''<?xml version="1.0" encoding="utf-8"?>
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
    <!-- ChillApp executable principal -->
    <Allow ID="ID_ALLOW_CHILLAPP"
           FriendlyName="ChillApp.exe"
           FileName="chillapp.exe"
           MinimumFileVersion="1.0.0.0" />

    <!-- Daemon Go Tailscale -->
    <Allow ID="ID_ALLOW_DAEMON"
           FriendlyName="chill-tailscale.exe"
           FileName="chill-tailscale.exe"
           MinimumFileVersion="1.0.0.0" />

    <!-- Flutter runtime DLL -->
    <Allow ID="ID_ALLOW_FLUTTER"
           FriendlyName="flutter_windows.dll"
           FileName="flutter_windows.dll" />
  </FileRules>

  <Signers>
    <!-- Ajouter le certificat de signature ici apres obtention -->
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
</SiPolicy>''';

  // ---------------------------------------------------------
  // Script PowerShell de deploiement
  // ---------------------------------------------------------

  /// Script PowerShell pour deployer la politique WDAC.
  ///
  /// Doit etre execute en tant qu'administrateur.
  /// Necessite un redemarrage pour activation.
  static const String deployScript = r'''
# ChillApp - Deploiement politique WDAC
# Executer en tant qu'administrateur

$policyPath  = "$env:TEMP\ChillAppWDAC.xml"
$binaryPath  = "$env:TEMP\ChillAppWDAC.bin"
$systemPath  = "$env:windir\System32\CodeIntegrity\SIPolicy.p7b"

# 1. Convertir en binaire
ConvertFrom-CIPolicy -XmlFilePath $policyPath -BinaryFilePath $binaryPath

# 2. Deployer (mode audit — pas de blocage, juste la journalisation)
Copy-Item $binaryPath $systemPath -Force

Write-Output "WDAC policy deployed in AUDIT mode. Restart required."
Write-Output "Monitor Event Viewer > Applications and Services Logs > Microsoft > Windows > CodeIntegrity"
''';

  // ---------------------------------------------------------
  // Deploiement runtime
  // ---------------------------------------------------------

  /// Deploie la politique WDAC en mode audit via PowerShell eleve.
  ///
  /// Le mode audit journalise les blocages sans les appliquer,
  /// ce qui permet de valider la politique avant de l'enforcer.
  ///
  /// Retourne true si le deploiement a reussi.
  /// Retourne false si on n'est pas sur Windows ou si une erreur survient.
  static Future<bool> deployAuditMode() async {
    if (!Platform.isWindows) return false;

    try {
      final tempDir = await Directory.systemTemp.createTemp('chill-wdac-');
      final policyFile = File('${tempDir.path}\\ChillAppWDAC.xml');
      await policyFile.writeAsString(policyXml);

      final policyPath = policyFile.path;
      final binPath = '${tempDir.path}\\ChillAppWDAC.bin';
      final sysPath = r'$env:windir\System32\CodeIntegrity\SIPolicy.p7b';

      final result = await Process.run('powershell', [
        '-NonInteractive',
        '-Command',
        "Start-Process powershell -Verb RunAs -Wait -ArgumentList "
            "'-NonInteractive -Command "
            "ConvertFrom-CIPolicy -XmlFilePath ''$policyPath'' "
            "-BinaryFilePath ''$binPath''; "
            "Copy-Item ''$binPath'' ''$sysPath'' -Force'",
      ]);

      // Nettoyage du repertoire temporaire
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Verifie si une politique WDAC est actuellement active.
  ///
  /// Interroge `Win32_DeviceGuard` via CIM.
  /// Valeurs possibles :
  /// - 0 = desactivee
  /// - 1 = audit mode
  /// - 2 = enforced
  ///
  /// Retourne false sur les OS non-Windows.
  static Future<bool> isWdacActive() async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('powershell', [
        '-NonInteractive',
        '-Command',
        'Get-CimInstance -ClassName Win32_DeviceGuard '
            '-Namespace root\\Microsoft\\Windows\\DeviceGuard | '
            'Select-Object -ExpandProperty CodeIntegrityPolicyEnforcementStatus',
      ]);

      final status =
          int.tryParse(result.stdout.toString().trim()) ?? 0;
      return status > 0;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------
  // Validation de la politique (testable sans deployment)
  // ---------------------------------------------------------

  /// Valide la structure de la politique WDAC sans la deployer.
  ///
  /// Verifie que les elements obligatoires sont presents dans le XML.
  /// Utilise pour les tests unitaires et la validation CI/CD.
  static WdacValidationResult validatePolicyXml(String xml) {
    final issues = <String>[];

    // Elements obligatoires
    final required = [
      '<SiPolicy',
      '<Rules>',
      '<FileRules>',
      'ID_ALLOW_CHILLAPP',
      'ID_ALLOW_DAEMON',
      'ID_ALLOW_FLUTTER',
      '<SigningScenarios>',
    ];

    for (final element in required) {
      if (!xml.contains(element)) {
        issues.add('Element manquant : $element');
      }
    }

    // Verifier que le mode audit est present
    if (!xml.contains('Audit Mode')) {
      issues.add('La politique doit commencer en mode audit');
    }

    // Verifier UMCI
    if (!xml.contains('Enabled:UMCI')) {
      issues.add('UMCI (User Mode Code Integrity) doit etre active');
    }

    return WdacValidationResult(
      isValid: issues.isEmpty,
      issues: issues,
    );
  }

  /// Extrait la liste des fichiers autorises dans la politique.
  ///
  /// Retourne les noms de fichiers declares dans les balises `<Allow>`.
  static List<String> extractAllowedFiles(String xml) {
    final allowed = <String>[];
    final pattern = RegExp(r'FileName="([^"]+)"');
    for (final match in pattern.allMatches(xml)) {
      allowed.add(match.group(1)!);
    }
    return allowed;
  }
}
