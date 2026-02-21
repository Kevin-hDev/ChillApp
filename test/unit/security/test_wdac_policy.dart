// Tests FIX-026 : WDAC Policy (Windows Defender Application Control)
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/wdac_policy.dart';

void main() {
  // =========================================================
  // policyXml — structure du template
  // =========================================================
  group('WdacPolicyDeployer.policyXml', () {
    test('est un XML valide (commence et finit correctement)', () {
      expect(WdacPolicyDeployer.policyXml, startsWith('<?xml'));
      expect(WdacPolicyDeployer.policyXml, endsWith('</SiPolicy>'));
    });

    test('contient la balise SiPolicy avec namespace', () {
      expect(
        WdacPolicyDeployer.policyXml,
        contains('xmlns="urn:schemas-microsoft-com:sipolicy"'),
      );
    });

    test('autorise chillapp.exe', () {
      expect(
        WdacPolicyDeployer.policyXml,
        contains('FileName="chillapp.exe"'),
      );
    });

    test('autorise le daemon Go', () {
      expect(
        WdacPolicyDeployer.policyXml,
        contains('FileName="chill-tailscale.exe"'),
      );
    });

    test('autorise la DLL Flutter', () {
      expect(
        WdacPolicyDeployer.policyXml,
        contains('FileName="flutter_windows.dll"'),
      );
    });

    test('est en mode audit par defaut (pas directement en enforce)', () {
      expect(WdacPolicyDeployer.policyXml, contains('Enabled:Audit Mode'));
      expect(WdacPolicyDeployer.policyXml, isNot(contains('Enabled:Unsigned System Integrity Policy')));
    });

    test('active UMCI (User Mode Code Integrity)', () {
      expect(WdacPolicyDeployer.policyXml, contains('Enabled:UMCI'));
    });
  });

  // =========================================================
  // deployScript — script PowerShell
  // =========================================================
  group('WdacPolicyDeployer.deployScript', () {
    test('contient ConvertFrom-CIPolicy', () {
      expect(WdacPolicyDeployer.deployScript, contains('ConvertFrom-CIPolicy'));
    });

    test('mentionne le chemin CodeIntegrity systeme', () {
      expect(
        WdacPolicyDeployer.deployScript,
        contains('CodeIntegrity'),
      );
    });

    test('mentionne le redemarrage requis', () {
      expect(WdacPolicyDeployer.deployScript, contains('Restart'));
    });
  });

  // =========================================================
  // validatePolicyXml — validation sans deploiement
  // =========================================================
  group('WdacPolicyDeployer.validatePolicyXml', () {
    test('valide le template par defaut sans erreur', () {
      final result =
          WdacPolicyDeployer.validatePolicyXml(WdacPolicyDeployer.policyXml);
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('detecte un XML vide comme invalide', () {
      final result = WdacPolicyDeployer.validatePolicyXml('');
      expect(result.isValid, isFalse);
      expect(result.issues, isNotEmpty);
    });

    test('detecte l absence de SiPolicy', () {
      const xml = '<Root><Rules/></Root>';
      final result = WdacPolicyDeployer.validatePolicyXml(xml);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.contains('SiPolicy')),
        isTrue,
      );
    });

    test('detecte l absence du mode audit', () {
      // XML avec tout sauf Audit Mode
      const xml = '''<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy">
  <Rules>
    <Rule><Option>Enabled:UMCI</Option></Rule>
  </Rules>
  <FileRules>
    <Allow ID="ID_ALLOW_CHILLAPP" FileName="chillapp.exe" />
    <Allow ID="ID_ALLOW_DAEMON" FileName="chill-tailscale.exe" />
    <Allow ID="ID_ALLOW_FLUTTER" FileName="flutter_windows.dll" />
  </FileRules>
  <SigningScenarios />
</SiPolicy>''';
      final result = WdacPolicyDeployer.validatePolicyXml(xml);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.contains('audit')),
        isTrue,
      );
    });

    test('detecte l absence de ID_ALLOW_CHILLAPP', () {
      final xmlSansChillApp = WdacPolicyDeployer.policyXml
          .replaceAll('ID_ALLOW_CHILLAPP', 'ID_ALLOW_OTHER');
      final result = WdacPolicyDeployer.validatePolicyXml(xmlSansChillApp);
      expect(result.isValid, isFalse);
    });
  });

  // =========================================================
  // extractAllowedFiles — extraction de la whitelist
  // =========================================================
  group('WdacPolicyDeployer.extractAllowedFiles', () {
    test('extrait les 3 fichiers autorises du template', () {
      final files = WdacPolicyDeployer.extractAllowedFiles(
        WdacPolicyDeployer.policyXml,
      );
      expect(files, contains('chillapp.exe'));
      expect(files, contains('chill-tailscale.exe'));
      expect(files, contains('flutter_windows.dll'));
    });

    test('retourne une liste vide pour un XML sans FileRules', () {
      const xml = '<SiPolicy><Rules/></SiPolicy>';
      final files = WdacPolicyDeployer.extractAllowedFiles(xml);
      expect(files, isEmpty);
    });

    test('retourne exactement 3 fichiers pour le template', () {
      final files = WdacPolicyDeployer.extractAllowedFiles(
        WdacPolicyDeployer.policyXml,
      );
      expect(files.length, equals(3));
    });
  });

  // =========================================================
  // WdacValidationResult
  // =========================================================
  group('WdacValidationResult', () {
    test('isValid = true quand issues est vide', () {
      const result = WdacValidationResult(isValid: true);
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('isValid = false quand il y a des issues', () {
      const result = WdacValidationResult(
        isValid: false,
        issues: ['Element manquant : SiPolicy'],
      );
      expect(result.isValid, isFalse);
      expect(result.issues, hasLength(1));
    });
  });
}
