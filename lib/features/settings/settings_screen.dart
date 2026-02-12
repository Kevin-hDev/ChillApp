import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../i18n/locale_provider.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isDark = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go('/'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t(locale, 'settings.title'),
                      style: theme.textTheme.headlineLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Thème
                Card(
                  child: ListTile(
                    leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                    title: Text(t(locale, 'settings.theme')),
                    subtitle: Text(isDark
                        ? t(locale, 'settings.themeDark')
                        : t(locale, 'settings.themeLight')),
                    trailing: Switch(
                      value: isDark,
                      onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Langue
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(t(locale, 'settings.language')),
                    subtitle: Text(locale == 'fr'
                        ? t(locale, 'settings.langFr')
                        : t(locale, 'settings.langEn')),
                    trailing: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'fr', label: Text(t(locale, 'settings.langFr'))),
                        ButtonSegment(value: 'en', label: Text(t(locale, 'settings.langEn'))),
                      ],
                      selected: {locale},
                      onSelectionChanged: (selection) {
                        ref.read(localeProvider.notifier).setLocale(selection.first);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
