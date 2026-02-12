import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/design_tokens.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'features/lock/lock_provider.dart';
import 'features/lock/lock_screen.dart';
import 'features/settings/settings_provider.dart';

class ChillApp extends ConsumerWidget {
  const ChillApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider);
    final lockState = ref.watch(lockProvider);
    final themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    final borderColor =
        isDark ? ChillColorsDark.border : ChillColorsLight.border;

    // Attendre que l'etat du lock soit charge depuis SharedPreferences
    if (lockState.isLoading) {
      return _withWindowBorder(
        borderColor,
        MaterialApp(
          title: 'Chill',
          debugShowCheckedModeBanner: false,
          theme: chillLightTheme(),
          darkTheme: chillDarkTheme(),
          themeMode: themeMode,
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    if (lockState.isEnabled && !lockState.isUnlocked) {
      return _withWindowBorder(
        borderColor,
        MaterialApp(
          title: 'Chill',
          debugShowCheckedModeBanner: false,
          theme: chillLightTheme(),
          darkTheme: chillDarkTheme(),
          themeMode: themeMode,
          home: const LockScreen(),
        ),
      );
    }

    return _withWindowBorder(
      borderColor,
      MaterialApp.router(
        title: 'Chill',
        debugShowCheckedModeBanner: false,
        theme: chillLightTheme(),
        darkTheme: chillDarkTheme(),
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }

  /// Fine bordure autour de la fenêtre pour délimiter les bords
  /// sur les fonds sombres (comme Warp terminal)
  Widget _withWindowBorder(Color borderColor, Widget child) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ClipRRect(child: child),
    );
  }
}
