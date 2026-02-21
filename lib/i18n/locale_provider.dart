import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';

/// Provider pour la langue active
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<String> {
  static const _supportedLocales = ['fr', 'en'];

  @override
  String build() {
    _load();
    return 'en'; // anglais par défaut
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('locale') ?? 'en';
    if (_supportedLocales.contains(saved)) {
      state = saved;
    } else {
      debugPrint('[i18n] Invalid saved locale: $saved, using default');
      state = 'fr';
    }
  }

  Future<void> setLocale(String locale) async {
    if (!_supportedLocales.contains(locale)) {
      debugPrint('[i18n] Invalid locale: $locale, ignoring');
      return;
    }
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }
}

/// Fonction helper pour accéder aux traductions
String t(String locale, String key) {
  final result = translations[locale]?[key] ?? translations['fr']?[key];
  if (result == null) {
    debugPrint('[i18n] Missing translation key: $key for locale: $locale');
  }
  return result ?? key;
}
