import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'features/settings/settings_provider.dart';

class ChillApp extends ConsumerWidget {
  const ChillApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Chill',
      debugShowCheckedModeBanner: false,
      theme: chillLightTheme(),
      darkTheme: chillDarkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}
