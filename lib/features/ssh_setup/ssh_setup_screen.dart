import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/design_tokens.dart';
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
import 'ssh_setup_provider.dart';

class SshSetupScreen extends ConsumerWidget {
  const SshSetupScreen({super.key});

  /// Convertit un ID d'etape en cle de traduction
  String _stepLabel(String locale, String stepId) {
    final key = 'ssh.step.$stepId';
    return t(locale, key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final sshState = ref.watch(sshSetupProvider);
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
                                t(locale, 'ssh.title'),
                                style: theme.textTheme.headlineLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(locale, 'ssh.intro'),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),

                        // Contenu
                        // Carte explicative
                        ExplanationCard(
                          titleKey: 'ssh.explanation.title',
                          contentKey: 'ssh.explanation.content',
                          locale: locale,
                        ),
                        const SizedBox(height: 24),

                        // Bouton "Tout configurer" ou "Reessayer"
                        if (!sshState.isRunning && !sshState.isComplete)
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  ref.read(sshSetupProvider.notifier).runAll(),
                              icon: Icon(
                                sshState.errorMessage != null
                                    ? Icons.refresh
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                sshState.errorMessage != null
                                    ? t(locale, 'ssh.error.retry')
                                    : t(locale, 'ssh.configureAll'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),

                        // Message d'erreur global
                        if (sshState.errorMessage != null &&
                            !sshState.isRunning) ...[
                          const SizedBox(height: 16),
                          ErrorBanner(message: sshState.errorMessage!),
                        ],

                        const SizedBox(height: 24),

                        // Loader anime + message de patience
                        if (sshState.isRunning) ...[
                          const AnimatedLoader(),
                          const SizedBox(height: 12),
                          PatienceMessage(
                            text: t(locale, 'ssh.patience'),
                            color: context.chillAccent,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Liste des etapes (visible des qu'on lance)
                        if (sshState.steps.any(
                          (s) => s.status != StepStatus.pending,
                        )) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: context.chillBgElevated,
                              borderRadius: BorderRadius.circular(
                                ChillRadius.xl,
                              ),
                              border: Border.all(color: context.chillBorder),
                            ),
                            child: Column(
                              children: sshState.steps.map((step) {
                                return StepIndicator(
                                  label: _stepLabel(locale, step.id),
                                  status: step.status,
                                );
                              }).toList(),
                            ),
                          ),
                        ],

                        // Resultat final
                        if (sshState.isComplete) ...[
                          const SizedBox(height: 24),
                          _ResultCard(
                            locale: locale,
                            ipEthernet: sshState.ipEthernet,
                            ipWifi: sshState.ipWifi,
                            username: sshState.username,
                          ),
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

/// Carte resultat avec IPs Ethernet/WiFi et nom d'utilisateur
class _ResultCard extends StatelessWidget {
  final String locale;
  final String? ipEthernet;
  final String? ipWifi;
  final String? username;

  const _ResultCard({
    required this.locale,
    this.ipEthernet,
    this.ipWifi,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = context.chillAccent;
    final connectEthernet = username != null && ipEthernet != null
        ? '$username@$ipEthernet'
        : '';
    final connectWifi = username != null && ipWifi != null
        ? '$username@$ipWifi'
        : '';

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
                t(locale, 'ssh.result.title'),
                style: theme.textTheme.headlineSmall?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // IP Ethernet
          if (ipEthernet != null) ...[
            Text(
              t(locale, 'ssh.result.ipEthernet'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            CopyableInfo(value: ipEthernet!, locale: locale),
            const SizedBox(height: 16),
          ],

          // IP WiFi
          if (ipWifi != null) ...[
            Text(
              t(locale, 'ssh.result.ipWifi'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            CopyableInfo(value: ipWifi!, locale: locale),
            const SizedBox(height: 16),
          ],

          // Username
          if (username != null) ...[
            Text(
              t(locale, 'ssh.result.username'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            CopyableInfo(value: username!, locale: locale),
            const SizedBox(height: 16),
          ],

          // Connexion Ethernet
          if (connectEthernet.isNotEmpty) ...[
            Text(
              t(locale, 'ssh.result.connectEthernet'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            CopyableInfo(value: connectEthernet, locale: locale),
            const SizedBox(height: 16),
          ],

          // Connexion WiFi
          if (connectWifi.isNotEmpty) ...[
            Text(
              t(locale, 'ssh.result.connectWifi'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            CopyableInfo(value: connectWifi, locale: locale),
          ],
        ],
      ),
    );
  }
}
