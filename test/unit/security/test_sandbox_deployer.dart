import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/sandbox_deployer.dart';

void main() {
  group('SandboxDeployer — profil AppArmor', () {
    test('1. appArmorProfile nest pas vide', () {
      expect(SandboxDeployer.appArmorProfile, isNotEmpty);
    });

    test('2. appArmorProfile contient la declaration du profil', () {
      expect(
        SandboxDeployer.appArmorProfile,
        contains('profile chillapp'),
      );
    });

    test('3. appArmorProfile interdit la lecture de /etc/shadow', () {
      expect(
        SandboxDeployer.appArmorProfile,
        contains('deny /etc/shadow'),
      );
    });

    test('4. appArmorProfile interdit ptrace', () {
      expect(
        SandboxDeployer.appArmorProfile,
        contains('deny ptrace'),
      );
    });

    test('5. appArmorProfile contient les regles reseau', () {
      expect(
        SandboxDeployer.appArmorProfile,
        contains('network inet stream'),
      );
    });
  });

  group('SandboxDeployer — entitlements macOS', () {
    test('6. macOSEntitlements est du XML valide (contient <?xml)', () {
      expect(
        SandboxDeployer.macOSEntitlements,
        contains('<?xml'),
      );
    });

    test('7. macOSEntitlements contient app-sandbox', () {
      expect(
        SandboxDeployer.macOSEntitlements,
        contains('com.apple.security.app-sandbox'),
      );
    });

    test('8. macOSEntitlements desactive la camera', () {
      expect(
        SandboxDeployer.macOSEntitlements,
        contains('<key>com.apple.security.device.camera</key>'),
      );
      // La valeur qui suit la cle camera doit etre false
      final content = SandboxDeployer.macOSEntitlements;
      final keyIndex =
          content.indexOf('<key>com.apple.security.device.camera</key>');
      expect(keyIndex, greaterThan(-1));
      final afterKey = content
          .substring(keyIndex + 'com.apple.security.device.camera'.length + 11)
          .trimLeft();
      expect(afterKey, startsWith('<false/>'));
    });

    test('9. macOSEntitlements desactive le microphone', () {
      expect(
        SandboxDeployer.macOSEntitlements,
        contains('<key>com.apple.security.device.microphone</key>'),
      );
      final content = SandboxDeployer.macOSEntitlements;
      final keyIndex =
          content.indexOf('<key>com.apple.security.device.microphone</key>');
      expect(keyIndex, greaterThan(-1));
      final afterKey = content
          .substring(
              keyIndex + 'com.apple.security.device.microphone'.length + 11)
          .trimLeft();
      expect(afterKey, startsWith('<false/>'));
    });

    test('10. macOSEntitlements active network.client', () {
      expect(
        SandboxDeployer.macOSEntitlements,
        contains('com.apple.security.network.client'),
      );
      final content = SandboxDeployer.macOSEntitlements;
      final keyIndex =
          content.indexOf('<key>com.apple.security.network.client</key>');
      expect(keyIndex, greaterThan(-1));
      final afterKey = content
          .substring(
              keyIndex + 'com.apple.security.network.client'.length + 11)
          .trimLeft();
      expect(afterKey, startsWith('<true/>'));
    });
  });

  group('SandboxDeployer — validateAppArmorProfile', () {
    test('11. validateAppArmorProfile retourne une liste vide pour un profil valide',
        () {
      final issues =
          SandboxDeployer.validateAppArmorProfile(SandboxDeployer.appArmorProfile);
      expect(issues, isEmpty);
    });

    test('12. validateAppArmorProfile retourne des erreurs pour un profil invalide',
        () {
      const badProfile = 'some random content without required rules';
      final issues = SandboxDeployer.validateAppArmorProfile(badProfile);
      expect(issues, isNotEmpty);
      expect(issues, contains('Missing profile declaration'));
      expect(issues, contains('Missing shadow file deny rule'));
      expect(issues, contains('Missing ptrace deny rule'));
      expect(issues, contains('Missing network rule'));
      expect(issues, contains('Missing base abstractions'));
    });
  });

  group('SandboxDeployer — validateMacOSEntitlements', () {
    test('13. validateMacOSEntitlements retourne une liste vide pour des entitlements valides',
        () {
      final issues = SandboxDeployer.validateMacOSEntitlements(
          SandboxDeployer.macOSEntitlements);
      expect(issues, isEmpty);
    });

    test('14. validateMacOSEntitlements retourne une erreur si app-sandbox manque',
        () {
      const badEntitlements = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
''';
      final issues = SandboxDeployer.validateMacOSEntitlements(badEntitlements);
      expect(issues, contains('Missing app-sandbox entitlement'));
    });

    test('15. _entitlementIsFalse detecte correctement une valeur false', () {
      const content = '''<dict>
  <key>com.apple.security.device.camera</key>
  <false/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>''';

      // La camera doit etre false
      expect(
        SandboxDeployer.validateMacOSEntitlements('''<?xml version="1.0"?>
<plist><dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.device.camera</key>
  <false/>
  <key>com.apple.security.device.microphone</key>
  <false/>
</dict></plist>'''),
        isEmpty,
        reason: 'Camera et microphone a false ne doivent pas generer d erreur',
      );

      // Si camera est true, cela doit etre signale
      final issuesWithCamera = SandboxDeployer.validateMacOSEntitlements('''<?xml version="1.0"?>
<plist><dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.device.camera</key>
  <true/>
  <key>com.apple.security.device.microphone</key>
  <false/>
</dict></plist>''');
      expect(issuesWithCamera, contains('Camera should be disabled'));

      // Utilisation indirecte de _entitlementIsFalse via le contenu reel
      expect(content, contains('<key>com.apple.security.device.camera</key>'));
    });
  });
}
