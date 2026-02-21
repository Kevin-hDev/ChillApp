import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chill_app/app.dart';
import 'package:chill_app/features/dashboard/dashboard_provider.dart';
import 'package:chill_app/features/lock/lock_provider.dart' as lock;
import 'package:chill_app/features/onboarding/onboarding_provider.dart';
import 'package:chill_app/features/settings/settings_provider.dart';
import 'package:chill_app/features/tailscale/tailscale_provider.dart';

/// Notifier de test : pas de commandes système (évite les timers pendants)
class _TestDashboardNotifier extends DashboardNotifier {
  @override
  DashboardState build() {
    return const DashboardState();
  }
}

/// Notifier de test : pas de daemon Tailscale
class _TestTailscaleNotifier extends TailscaleNotifier {
  @override
  TailscaleState build() {
    return const TailscaleState(status: TailscaleConnectionStatus.error);
  }
}

/// Notifier de test : lock deja charge, pas de PIN actif
class _TestLockNotifier extends lock.LockNotifier {
  @override
  lock.LockState build() {
    return const lock.LockState(isLoading: false);
  }
}

/// Notifier de test : onboarding deja vu
class _TestOnboardingNotifier extends OnboardingNotifier {
  @override
  bool build() {
    return true; // deja vu
  }
}

void main() {
  testWidgets('App loads dashboard', (WidgetTester tester) async {
    // Surface plus grande pour éviter les overflow en test
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          dashboardProvider.overrideWith(() => _TestDashboardNotifier()),
          tailscaleProvider.overrideWith(() => _TestTailscaleNotifier()),
          lock.lockProvider.overrideWith(() => _TestLockNotifier()),
          onboardingProvider.overrideWith(() => _TestOnboardingNotifier()),
        ],
        child: const ChillApp(),
      ),
    );
    // pump au lieu de pumpAndSettle car les animations tournent en boucle
    await tester.pump(const Duration(milliseconds: 500));

    // Le texte depend de la locale du systeme (FR ou EN)
    final frWelcome = find.text('Bienvenue sur Chill');
    final enWelcome = find.text('Welcome to Chill');
    expect(
      frWelcome.evaluate().isNotEmpty || enWelcome.evaluate().isNotEmpty,
      true,
      reason: 'Expected welcome text in FR or EN',
    );

    // Démonter le widget tree pour arrêter les timers des animations
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
