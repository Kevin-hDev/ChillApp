import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_provider.dart';

/// Provider pour savoir si l'onboarding a été vu
final onboardingProvider =
    NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.read(sharedPrefsProvider);
    return prefs.getBool('onboardingDone') ?? false;
  }

  Future<void> complete() async {
    state = true;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool('onboardingDone', true);
  }
}
