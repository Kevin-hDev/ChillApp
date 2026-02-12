import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/i18n/translations.dart';

void main() {
  group('Traductions', () {
    test('FR et EN ont le même nombre de clés', () {
      final fr = translations['fr']!;
      final en = translations['en']!;
      expect(fr.length, en.length,
          reason: 'FR a ${fr.length} clés, EN a ${en.length} clés');
    });

    test('toutes les clés FR existent en EN', () {
      final fr = translations['fr']!;
      final en = translations['en']!;
      final missingInEn = <String>[];
      for (final key in fr.keys) {
        if (!en.containsKey(key)) {
          missingInEn.add(key);
        }
      }
      expect(missingInEn, isEmpty,
          reason: 'Clés manquantes en EN : $missingInEn');
    });

    test('toutes les clés EN existent en FR', () {
      final fr = translations['fr']!;
      final en = translations['en']!;
      final missingInFr = <String>[];
      for (final key in en.keys) {
        if (!fr.containsKey(key)) {
          missingInFr.add(key);
        }
      }
      expect(missingInFr, isEmpty,
          reason: 'Clés manquantes en FR : $missingInFr');
    });

    test('aucune valeur vide en FR', () {
      final fr = translations['fr']!;
      final emptyKeys = <String>[];
      for (final entry in fr.entries) {
        if (entry.value.trim().isEmpty) {
          emptyKeys.add(entry.key);
        }
      }
      expect(emptyKeys, isEmpty,
          reason: 'Clés avec valeur vide en FR : $emptyKeys');
    });

    test('aucune valeur vide en EN', () {
      final en = translations['en']!;
      final emptyKeys = <String>[];
      for (final entry in en.entries) {
        if (entry.value.trim().isEmpty) {
          emptyKeys.add(entry.key);
        }
      }
      expect(emptyKeys, isEmpty,
          reason: 'Clés avec valeur vide en EN : $emptyKeys');
    });

    test('les clés critiques existent', () {
      final fr = translations['fr']!;
      final criticalKeys = [
        'app.title',
        'dashboard.welcome',
        'ssh.title',
        'ssh.configureAll',
        'wol.title',
        'wol.configureAll',
        'wol.biosWarning',
        'wol.notAvailableMac',
        'wol.linuxWarning',
        'info.title',
        'info.ipEthernet',
        'info.ipWifi',
        'info.refresh',
        'settings.title',
        'status.configured',
        'status.notConfigured',
      ];
      for (final key in criticalKeys) {
        expect(fr.containsKey(key), true,
            reason: 'Clé critique manquante : $key');
      }
    });

    test('les langues supportées sont FR et EN', () {
      expect(translations.keys, containsAll(['fr', 'en']));
      expect(translations.length, 2);
    });
  });
}
