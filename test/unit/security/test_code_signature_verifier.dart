// Tests FIX-018/019 : Code Signature Verifier + Packaging
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/code_signature_verifier.dart';

void main() {
  // =========================================================
  // SignatureStatus enum
  // =========================================================
  group('SignatureStatus', () {
    test('contient les 4 statuts requis', () {
      expect(SignatureStatus.values, contains(SignatureStatus.valid));
      expect(SignatureStatus.values, contains(SignatureStatus.invalid));
      expect(SignatureStatus.values, contains(SignatureStatus.unsigned));
      expect(SignatureStatus.values, contains(SignatureStatus.error));
    });
  });

  // =========================================================
  // SignatureResult
  // =========================================================
  group('SignatureResult', () {
    test('isValid retourne true uniquement pour le statut valid', () {
      expect(
        const SignatureResult(status: SignatureStatus.valid).isValid,
        isTrue,
      );
      expect(
        const SignatureResult(status: SignatureStatus.invalid).isValid,
        isFalse,
      );
      expect(
        const SignatureResult(status: SignatureStatus.unsigned).isValid,
        isFalse,
      );
      expect(
        const SignatureResult(status: SignatureStatus.error).isValid,
        isFalse,
      );
    });

    test('details est vide par defaut', () {
      const result = SignatureResult(status: SignatureStatus.valid);
      expect(result.details, isEmpty);
    });

    test('details peut contenir un message', () {
      const result = SignatureResult(
        status: SignatureStatus.error,
        details: 'gpg: command not found',
      );
      expect(result.details, equals('gpg: command not found'));
    });

    test('toString inclut le statut et les details', () {
      const result = SignatureResult(
        status: SignatureStatus.unsigned,
        details: 'Pas de fichier .sig',
      );
      final str = result.toString();
      expect(str, contains('unsigned'));
      expect(str, contains('Pas de fichier .sig'));
    });

    test('statut error est non-valide', () {
      const result = SignatureResult(
        status: SignatureStatus.error,
        details: 'Plateforme non supportee',
      );
      expect(result.isValid, isFalse);
      expect(result.status, equals(SignatureStatus.error));
    });
  });

  // =========================================================
  // Templates de packaging (constantes)
  // =========================================================
  group('msixConfig', () {
    test('contient les champs obligatoires MSIX', () {
      expect(msixConfig, contains('display_name: ChillApp'));
      expect(msixConfig, contains('identity_name: com.chill.chillapp'));
      expect(msixConfig, contains('msix_version'));
    });

    test('ne declare pas de capabilities dangereuses en actif', () {
      // Les capabilities dangereuses ne doivent pas etre declarees activement
      // (elles peuvent apparaitre dans des commentaires d'avertissement)
      final lines = msixConfig
          .split('\n')
          .where((l) => !l.trim().startsWith('#'))
          .join('\n');
      expect(lines, isNot(contains('runFullTrust')));
      expect(lines, isNot(contains('allJoynRouter')));
    });
  });

  group('windowsBuildScript', () {
    test('inclut les options de build securise', () {
      expect(windowsBuildScript, contains('--release'));
      expect(windowsBuildScript, contains('--obfuscate'));
      expect(windowsBuildScript, contains('--split-debug-info'));
    });

    test('mentionne la signature Authenticode', () {
      expect(windowsBuildScript, contains('signtool'));
      expect(windowsBuildScript, contains('Authenticode'));
    });
  });

  group('snapcraftConfig', () {
    test('utilise la confinement strict (AppArmor)', () {
      expect(snapcraftConfig, contains('confinement: strict'));
    });

    test('ne declare pas de plugs dangereux en actif', () {
      // Les plugs dangereux ne doivent pas etre actifs
      // (ils peuvent apparaitre dans des commentaires d'avertissement)
      final lines = snapcraftConfig
          .split('\n')
          .where((l) => !l.trim().startsWith('#'))
          .join('\n');
      expect(lines, isNot(contains('process-control')));
      expect(lines, isNot(contains('system-observe')));
      expect(lines, isNot(contains('mount-observe')));
    });

    test('contient les plugs reseau necessaires', () {
      expect(snapcraftConfig, contains('network'));
      expect(snapcraftConfig, contains('network-bind'));
    });
  });

  group('macosBuildScript', () {
    test('inclut les options de build securise', () {
      expect(macosBuildScript, contains('--release'));
      expect(macosBuildScript, contains('--obfuscate'));
    });

    test('mentionne la notarisation Apple', () {
      expect(macosBuildScript, contains('notarytool'));
      expect(macosBuildScript, contains('stapler'));
    });

    test('mentionne codesign avec Developer ID', () {
      expect(macosBuildScript, contains('codesign'));
      expect(macosBuildScript, contains('Developer ID'));
    });
  });

  group('linuxSignScript', () {
    test('mentionne la signature GPG', () {
      expect(linuxSignScript, contains('gpg'));
      expect(linuxSignScript, contains('--detach-sign'));
    });

    test('inclut la verification de la signature', () {
      expect(linuxSignScript, contains('--verify'));
    });
  });

  // =========================================================
  // CodeSignatureVerifier — plateforme courante
  // =========================================================
  group('CodeSignatureVerifier.verifyCurrentBinary', () {
    test('retourne un SignatureResult (pas une exception)', () async {
      // On ne peut pas controler le resultat (depend de l'OS et des outils),
      // mais la methode doit retourner sans lever d'exception.
      final result = await CodeSignatureVerifier.verifyCurrentBinary();
      expect(result, isA<SignatureResult>());
    });

    test('le statut est une valeur valide de SignatureStatus', () async {
      final result = await CodeSignatureVerifier.verifyCurrentBinary();
      expect(SignatureStatus.values, contains(result.status));
    });
  });
}
