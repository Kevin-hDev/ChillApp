import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    if (lockState.isEnabled && !lockState.isUnlocked) {
      return MaterialApp(
        title: 'Chill',
        debugShowCheckedModeBanner: false,
        theme: chillLightTheme(),
        darkTheme: chillDarkTheme(),
        themeMode: themeMode,
        home: const LockScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Chill',
      debugShowCheckedModeBanner: false,
      theme: chillLightTheme(),
      darkTheme: chillDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
