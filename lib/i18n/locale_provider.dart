import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';

/// Provider pour la langue active
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'fr'; // français par défaut
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('locale') ?? 'fr';
  }

  Future<void> setLocale(String locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }
}

/// Fonction helper pour accéder aux traductions
String t(String locale, String key) {
  return translations[locale]?[key] ?? translations['fr']?[key] ?? key;
}
