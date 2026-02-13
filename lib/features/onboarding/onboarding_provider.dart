import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider pour savoir si l'onboarding a été vu
final onboardingProvider =
    NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  // TODO: Remettre _load() quand le dev est terminé
  // Pour le dev : onboarding toujours visible
  @override
  bool build() {
    // _load();
    return false; // toujours afficher pendant le dev
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('onboardingDone') ?? false;
  }

  Future<void> complete() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingDone', true);
  }
}
