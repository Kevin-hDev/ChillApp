import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/design_tokens.dart';
import '../../core/os_detector.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/extensions/chill_theme.dart';
import '../../shared/helpers/responsive.dart';
import '../../shared/models/setup_step.dart';
import '../../shared/widgets/animated_loader.dart';
import '../../shared/widgets/copyable_info.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/explanation_card.dart';
import '../../shared/widgets/patience_message.dart';
import '../../shared/widgets/chill_background.dart';
import '../../shared/widgets/step_indicator.dart';
import 'wol_setup_provider.dart';

class WolSetupScreen extends ConsumerWidget {
  const WolSetupScreen({super.key});

  /// Convertit un ID d'etape en cle de traduction
  String _stepLabel(String locale, String stepId) {
    final key = 'wol.step.$stepId';
    return t(locale, key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final wolState = ref.watch(wolSetupProvider);
    final theme = Theme.of(context);
    final isMac = OsDetector.currentOS == SupportedOS.macos;

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
                    // Header avec bouton retour
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Retour',
                          onPressed: () => context.go('/'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(locale, 'wol.title'),
                            style: theme.textTheme.headlineLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(locale, 'wol.intro'),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),

                    // Contenu
                        // Carte explicative
                        ExplanationCard(
                          titleKey: 'wol.explanation.title',
                          contentKey: 'wol.explanation.content',
                          locale: locale,
                        ),
                        const SizedBox(height: 16),

                        // Avertissement BIOS (toujours visible)
                        _BiosWarningCard(locale: locale),

                        // Avertissement Linux (uniquement sur Linux)
                        if (OsDetector.currentOS == SupportedOS.linux) ...[
                          const SizedBox(height: 12),
                          _LinuxWarningCard(locale: locale),
                        ],
                        const SizedBox(height: 24),

                        // Sur Mac : message "non disponible"
                        if (isMac) ...[
                          _MacUnavailableCard(locale: locale),
                        ],

                        // Sur Windows/Linux : interface de configuration
                        if (!isMac) ...[
                          // Bouton "Tout configurer" ou "Reessayer"
                          if (!wolState.isRunning && !wolState.isComplete)
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () => ref.read(wolSetupProvider.notifier).runAll(),
                                icon: Icon(
                                  wolState.errorMessage != null ? Icons.refresh : Icons.play_arrow,
                                ),
                                label: Text(
                                  wolState.errorMessage != null
                                      ? t(locale, 'wol.error.retry')
                                      : t(locale, 'wol.configureAll'),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                ),
                              ),
                            ),

                          // Message d'erreur global
                          if (wolState.errorMessage != null && !wolState.isRunning) ...[
                            const SizedBox(height: 16),
                            ErrorBanner(message: wolState.errorMessage!),
                          ],

                          const SizedBox(height: 24),

                          // Loader anime + message de patience
                          if (wolState.isRunning) ...[
                            const AnimatedLoader(),
                            const SizedBox(height: 12),
                            PatienceMessage(
                              text: t(locale, 'wol.patience'),
                              color: context.chillAccent,
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Liste des etapes (visible des qu'on lance)
                          if (wolState.steps.any((s) => s.status != StepStatus.pending)) ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: context.chillBgElevated,
                                borderRadius: BorderRadius.circular(ChillRadius.xl),
                                border: Border.all(
                                  color: context.chillBorder,
                                ),
                              ),
                              child: Column(
                                children: wolState.steps.map((step) {
                                  return StepIndicator(
                                    label: _stepLabel(locale, step.id),
                                    status: step.status,
                                  );
                                }).toList(),
                              ),
                            ),
                          ],

                          // Resultat final
                          if (wolState.isComplete) ...[
                            const SizedBox(height: 24),
                            _ResultCard(
                              locale: locale,
                              macAddress: wolState.macAddress,
                              ipEthernet: wolState.ipEthernet,
                              ipWifi: wolState.ipWifi,
                              adapterName: wolState.adapterName,
                            ),
                            const SizedBox(height: 16),
                            _BiosTutorialCard(locale: locale),
                          ],
                        ],

                        const SizedBox(height: 32),
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
}

/// Avertissement BIOS (carte orange)
class _BiosWarningCard extends StatelessWidget {
  final String locale;

  const _BiosWarningCard({required this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orange = context.chillOrange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ChillRadius.lg),
        border: Border.all(color: orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t(locale, 'wol.biosWarning'),
              style: theme.textTheme.bodyMedium?.copyWith(color: orange, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avertissement Linux (WoL pas toujours fiable)
class _LinuxWarningCard extends StatelessWidget {
  final String locale;

  const _LinuxWarningCard({required this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blue = context.chillBlue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ChillRadius.lg),
        border: Border.all(color: blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t(locale, 'wol.linuxWarning'),
              style: theme.textTheme.bodyMedium?.copyWith(color: blue, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Message "Non disponible sur Mac"
class _MacUnavailableCard extends StatelessWidget {
  final String locale;

  const _MacUnavailableCard({required this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.chillBgElevated,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(
          color: context.chillBorder,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.desktop_mac_outlined,
            color: context.chillTextMuted,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            t(locale, 'wol.notAvailableMac'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.chillTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Bouton tutoriel BIOS avec icone custom
class _BiosTutorialCard extends StatelessWidget {
  final String locale;

  /// URL du tutoriel BIOS sur le site web
  /// TODO: Remplacer par l'URL definitive une fois le site deploye
  static const _biosTutorialUrl = 'https://chillshell.dev/tuto/bios';

  const _BiosTutorialCard({required this.locale});

  Future<void> _openTutorial() async {
    final uri = Uri.parse(_biosTutorialUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openTutorial,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.chillBgElevated,
            borderRadius: BorderRadius.circular(ChillRadius.xl),
            border: Border.all(color: context.chillBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(ChillRadius.md),
                child: Image.asset(
                  'assets/images/logo_bios.png',
                  width: 72,
                  height: 72,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(locale, 'wol.biosTutorial'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(locale, 'wol.biosTutorial.desc'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.chillTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: context.chillTextMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte resultat avec MAC, carte reseau, IPs et rappel BIOS
class _ResultCard extends StatelessWidget {
  final String locale;
  final String? macAddress;
  final String? ipEthernet;
  final String? ipWifi;
  final String? adapterName;

  const _ResultCard({
    required this.locale,
    this.macAddress,
    this.ipEthernet,
    this.ipWifi,
    this.adapterName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = context.chillAccent;
    final orange = context.chillOrange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: accent, size: 28),
              const SizedBox(width: 12),
              Text(
                t(locale, 'wol.result.title'),
                style: theme.textTheme.headlineSmall?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Adresse MAC
          if (macAddress != null) ...[
            Text(t(locale, 'wol.result.mac'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: macAddress!, locale: locale),
            const SizedBox(height: 16),
          ],

          // Carte reseau
          if (adapterName != null) ...[
            Text(t(locale, 'wol.result.adapter'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: adapterName!, locale: locale),
            const SizedBox(height: 16),
          ],

          // IP Ethernet
          if (ipEthernet != null) ...[
            Text(t(locale, 'wol.result.ipEthernet'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: ipEthernet!, locale: locale),
            const SizedBox(height: 16),
          ],

          // IP WiFi
          if (ipWifi != null) ...[
            Text(t(locale, 'wol.result.ipWifi'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: ipWifi!, locale: locale),
            const SizedBox(height: 16),
          ],

        ],
      ),
    );
  }
}
