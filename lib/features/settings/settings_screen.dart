import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/extensions/chill_theme.dart';
import '../../shared/helpers/responsive.dart';
import '../../shared/widgets/chill_background.dart';
import '../lock/lock_provider.dart';
import '../lock/lock_screen.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isDark = ref.watch(themeModeProvider);
    final lockState = ref.watch(lockProvider);
    final autostart = ref.watch(autostartProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: ChillBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = responsivePadding(width);

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Retour',
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

                        // Contenu
                        // Thème
                        Card(
                          child: ListTile(
                            leading: Icon(
                              isDark ? Icons.dark_mode : Icons.light_mode,
                            ),
                            title: Text(t(locale, 'settings.theme')),
                            subtitle: Text(
                              isDark
                                  ? t(locale, 'settings.themeDark')
                                  : t(locale, 'settings.themeLight'),
                            ),
                            trailing: Switch(
                              value: isDark,
                              onChanged: (_) =>
                                  ref.read(themeModeProvider.notifier).toggle(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Langue
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.language),
                            title: Text(t(locale, 'settings.language')),
                            subtitle: Text(
                              locale == 'fr'
                                  ? t(locale, 'settings.langFr')
                                  : t(locale, 'settings.langEn'),
                            ),
                            trailing: SegmentedButton<String>(
                              segments: [
                                ButtonSegment(
                                  value: 'fr',
                                  label: Text(t(locale, 'settings.langFr')),
                                ),
                                ButtonSegment(
                                  value: 'en',
                                  label: Text(t(locale, 'settings.langEn')),
                                ),
                              ],
                              selected: {locale},
                              onSelectionChanged: (selection) {
                                ref
                                    .read(localeProvider.notifier)
                                    .setLocale(selection.first);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Lancement au démarrage
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.play_circle_outline),
                            title: Text(t(locale, 'settings.autostart')),
                            subtitle: Text(
                              t(locale, 'settings.autostart.desc'),
                            ),
                            trailing: autostart == null
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.chillAccent,
                                    ),
                                  )
                                : Switch(
                                    value: autostart,
                                    onChanged: (_) => ref
                                        .read(autostartProvider.notifier)
                                        .toggle(),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Verrouillage PIN
                        Card(
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.lock_outline),
                                title: Text(t(locale, 'settings.lock')),
                                subtitle: Text(t(locale, 'settings.lock.desc')),
                                trailing: Switch(
                                  value: lockState.isEnabled,
                                  onChanged: (enabled) {
                                    if (enabled) {
                                      _showSetPinDialog(context, ref, locale);
                                    } else {
                                      _showDisablePinDialog(
                                        context,
                                        ref,
                                        locale,
                                      );
                                    }
                                  },
                                ),
                              ),
                              if (lockState.isEnabled)
                                ListTile(
                                  leading: const SizedBox(width: 24),
                                  title: Text(
                                    t(locale, 'settings.lock.change'),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showChangePinDialog(
                                    context,
                                    ref,
                                    locale,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Avertissement PIN
                        Card(
                          color: context.chillOrange.withValues(alpha: 0.08),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: context.chillOrange,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    t(locale, 'settings.lock.warning'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: context.chillTextSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSetPinDialog(BuildContext context, WidgetRef ref, String locale) {
    String? firstPin;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PinInputDialog(
              title: firstPin == null
                  ? t(locale, 'settings.lock.new')
                  : t(locale, 'settings.lock.confirm'),
              onComplete: (pin) async {
                if (firstPin == null) {
                  firstPin = pin;
                  setDialogState(() {});
                  // Force rebuild du dialog pour changer le titre
                  Navigator.of(ctx).pop();
                  _showConfirmPinDialog(context, ref, locale, firstPin!);
                }
              },
            );
          },
        );
      },
    );
  }

  void _showConfirmPinDialog(
    BuildContext context,
    WidgetRef ref,
    String locale,
    String firstPin,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final key = GlobalKey<PinInputDialogState>();
        return PinInputDialog(
          key: key,
          title: t(locale, 'settings.lock.confirm'),
          onComplete: (pin) async {
            if (pin == firstPin) {
              await ref.read(lockProvider.notifier).setPin(pin);
              if (ctx.mounted) Navigator.of(ctx).pop();
            } else {
              key.currentState?.setError(t(locale, 'settings.lock.mismatch'));
            }
          },
        );
      },
    );
  }

  void _showDisablePinDialog(
    BuildContext context,
    WidgetRef ref,
    String locale,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final key = GlobalKey<PinInputDialogState>();
        return PinInputDialog(
          key: key,
          title: t(locale, 'settings.lock.enterCurrent'),
          onComplete: (pin) async {
            final ok = await ref.read(lockProvider.notifier).verifyPin(pin);
            if (ok) {
              await ref.read(lockProvider.notifier).removePin();
              if (ctx.mounted) Navigator.of(ctx).pop();
            } else {
              key.currentState?.setError(t(locale, 'lock.error'));
            }
          },
        );
      },
    );
  }

  void _showChangePinDialog(
    BuildContext context,
    WidgetRef ref,
    String locale,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final key = GlobalKey<PinInputDialogState>();
        return PinInputDialog(
          key: key,
          title: t(locale, 'settings.lock.enterCurrent'),
          onComplete: (pin) async {
            final ok = await ref.read(lockProvider.notifier).verifyPin(pin);
            if (ok) {
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) _showSetPinDialog(context, ref, locale);
            } else {
              key.currentState?.setError(t(locale, 'lock.error'));
            }
          },
        );
      },
    );
  }
}
