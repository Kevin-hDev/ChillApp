import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/extensions/chill_theme.dart';
import '../../shared/helpers/responsive.dart';
import '../../shared/widgets/chill_background.dart';
import '../../shared/widgets/error_banner.dart';
import 'connection_info_provider.dart';

class ConnectionInfoScreen extends ConsumerWidget {
  const ConnectionInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final info = ref.watch(connectionInfoProvider);
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
                          onPressed: () => context.go('/'),
                          tooltip: 'Retour',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(locale, 'info.title'),
                            style: theme.textTheme.headlineLarge,
                          ),
                        ),
                        // Bouton Rafraîchir
                        IconButton(
                      icon: info.isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.chillAccent,
                              ),
                            )
                          : Icon(Icons.refresh, color: context.chillAccent),
                      onPressed: info.isLoading
                          ? null
                          : () => ref.read(connectionInfoProvider.notifier).fetchAll(force: true),
                      tooltip: t(locale, 'info.refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t(locale, 'info.intro'),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),

                // Contenu
                if (info.isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: context.chillAccent),
                          const SizedBox(height: 16),
                          Text(
                            '...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: context.chillTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!info.isLoading) ...[
                              // Erreur
                              if (info.error != null) ...[
                                ErrorBanner(message: info.error!),
                                const SizedBox(height: 24),
                              ],

                              // Carte principale avec toutes les infos
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: context.chillBgElevated,
                                  borderRadius: BorderRadius.circular(ChillRadius.xl),
                                  border: Border.all(color: context.chillBorder),
                                ),
                                child: Column(
                                  children: [
                                    // IP Ethernet
                                    _InfoRow(
                                      icon: Icons.settings_ethernet,
                                      label: t(locale, 'info.ipEthernet'),
                                      value: info.ipEthernet,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      locale: locale,
                                    ),
                                    const SizedBox(height: 20),

                                    // IP WiFi
                                    _InfoRow(
                                      icon: Icons.wifi,
                                      label: t(locale, 'info.ipWifi'),
                                      value: info.ipWifi,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      locale: locale,
                                    ),
                                    const SizedBox(height: 20),

                                    // MAC
                                    _InfoRow(
                                      icon: Icons.router,
                                      label: t(locale, 'info.mac'),
                                      value: info.macAddress,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      locale: locale,
                                    ),
                                    const SizedBox(height: 20),

                                    // Nom de la machine
                                    _InfoRow(
                                      icon: Icons.computer,
                                      label: t(locale, 'info.hostname'),
                                      value: info.hostname,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      locale: locale,
                                    ),
                                    const SizedBox(height: 20),

                                    // Utilisateur SSH
                                    _InfoRow(
                                      icon: Icons.terminal,
                                      label: t(locale, 'info.sshUser'),
                                      value: info.username,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      locale: locale,
                                      hint: t(locale, 'info.sshUserHint'),
                                    ),

                                    // Adapter (si trouvé)
                                    if (info.adapterName != null) ...[
                                      const SizedBox(height: 20),
                                      _InfoRow(
                                        icon: Icons.settings_ethernet,
                                        label: t(locale, 'info.adapter'),
                                        value: info.adapterName,
                                        notFoundLabel: t(locale, 'info.notFound'),
                                        locale: locale,
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Carte recommandation Tailscale
                              const SizedBox(height: 16),
                              _TailscaleRecommendCard(
                                locale: locale,
                                onTap: () => context.go('/tailscale'),
                              ),

                              const SizedBox(height: 32),
                ],
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

/// Ligne d'info avec icône, label, valeur et bouton copier
class _InfoRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String notFoundLabel;
  final String locale;
  final String? hint;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.notFoundLabel,
    required this.locale,
    this.hint,
  });

  @override
  State<_InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<_InfoRow> {
  bool _copied = false;

  void _copy() async {
    if (widget.value == null) return;
    await Clipboard.setData(ClipboardData(text: widget.value!));
    // Auto-clear clipboard after 3 seconds for security
    Future.delayed(const Duration(seconds: 3), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = widget.value != null && widget.value!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label avec icône
        Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: context.chillTextSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.chillTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Valeur avec bouton copier
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.chillBgSurface,
            borderRadius: BorderRadius.circular(ChillRadius.lg),
            border: Border.all(color: context.chillBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? widget.value! : widget.notFoundLabel,
                  style: hasValue
                      ? GoogleFonts.jetBrainsMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: context.chillTextPrimary,
                        )
                      : TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: context.chillTextMuted,
                        ),
                ),
              ),
              if (hasValue)
                IconButton(
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    color: _copied ? context.chillAccent : context.chillTextSecondary,
                    size: 18,
                  ),
                  onPressed: _copy,
                  tooltip: _copied
                      ? t(widget.locale, 'info.copied')
                      : t(widget.locale, 'info.copy'),
                ),
            ],
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.chillAccent,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Carte de recommandation Tailscale
class _TailscaleRecommendCard extends StatelessWidget {
  final String locale;
  final VoidCallback onTap;

  const _TailscaleRecommendCard({
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.chillAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: context.chillAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: context.chillAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(locale, 'info.recommend.title'),
                  style: theme.textTheme.titleMedium?.copyWith(color: context.chillAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t(locale, 'info.recommend.content'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.vpn_lock, size: 18),
              label: Text(t(locale, 'info.recommend.button')),
            ),
          ),
        ],
      ),
    );
  }
}
