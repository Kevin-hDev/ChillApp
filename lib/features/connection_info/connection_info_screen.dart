import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import 'connection_info_provider.dart';

class ConnectionInfoScreen extends ConsumerWidget {
  const ConnectionInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final info = ref.watch(connectionInfoProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header avec bouton retour
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go('/'),
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
                                color: accent,
                              ),
                            )
                          : Icon(Icons.refresh, color: accent),
                      onPressed: info.isLoading
                          ? null
                          : () => ref.read(connectionInfoProvider.notifier).fetchAll(),
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
                Expanded(
                  child: info.isLoading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: accent),
                              const SizedBox(height: 16),
                              Text(
                                '...',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? ChillColorsDark.textSecondary
                                      : ChillColorsLight.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              // Erreur
                              if (info.error != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: (isDark ? ChillColorsDark.red : ChillColorsLight.red)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(ChillRadius.lg),
                                    border: Border.all(
                                      color: (isDark ? ChillColorsDark.red : ChillColorsLight.red)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: isDark ? ChillColorsDark.red : ChillColorsLight.red),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          info.error!,
                                          style: TextStyle(
                                            color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Carte principale avec toutes les infos
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? ChillColorsDark.bgElevated
                                      : ChillColorsLight.bgElevated,
                                  borderRadius: BorderRadius.circular(ChillRadius.xl),
                                  border: Border.all(
                                    color: isDark
                                        ? ChillColorsDark.border
                                        : ChillColorsLight.border,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // IP Ethernet
                                    _InfoRow(
                                      icon: Icons.settings_ethernet,
                                      label: t(locale, 'info.ipEthernet'),
                                      value: info.ipEthernet,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 20),

                                    // IP WiFi
                                    _InfoRow(
                                      icon: Icons.wifi,
                                      label: t(locale, 'info.ipWifi'),
                                      value: info.ipWifi,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 20),

                                    // MAC
                                    _InfoRow(
                                      icon: Icons.router,
                                      label: t(locale, 'info.mac'),
                                      value: info.macAddress,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 20),

                                    // Username
                                    _InfoRow(
                                      icon: Icons.person,
                                      label: t(locale, 'info.username'),
                                      value: info.username,
                                      notFoundLabel: t(locale, 'info.notFound'),
                                      isDark: isDark,
                                    ),

                                    // Adapter (si trouvé)
                                    if (info.adapterName != null) ...[
                                      const SizedBox(height: 20),
                                      _InfoRow(
                                        icon: Icons.settings_ethernet,
                                        label: t(locale, 'info.adapter'),
                                        value: info.adapterName,
                                        notFoundLabel: t(locale, 'info.notFound'),
                                        isDark: isDark,
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),
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
  }
}

/// Ligne d'info avec icône, label, valeur et bouton copier
class _InfoRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String notFoundLabel;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.notFoundLabel,
    required this.isDark,
  });

  @override
  State<_InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<_InfoRow> {
  bool _copied = false;

  void _copy() async {
    if (widget.value == null) return;
    await Clipboard.setData(ClipboardData(text: widget.value!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.isDark ? ChillColorsDark.accent : ChillColorsLight.accent;
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
              color: widget.isDark
                  ? ChillColorsDark.textSecondary
                  : ChillColorsLight.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: widget.isDark
                    ? ChillColorsDark.textSecondary
                    : ChillColorsLight.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Valeur avec bouton copier
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isDark ? ChillColorsDark.bgSurface : ChillColorsLight.bgSurface,
            borderRadius: BorderRadius.circular(ChillRadius.lg),
            border: Border.all(
              color: widget.isDark ? ChillColorsDark.border : ChillColorsLight.border,
            ),
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
                          color: widget.isDark
                              ? ChillColorsDark.textPrimary
                              : ChillColorsLight.textPrimary,
                        )
                      : TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: widget.isDark
                              ? ChillColorsDark.textMuted
                              : ChillColorsLight.textMuted,
                        ),
                ),
              ),
              if (hasValue)
                IconButton(
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    color: _copied
                        ? accent
                        : (widget.isDark
                            ? ChillColorsDark.textSecondary
                            : ChillColorsLight.textSecondary),
                    size: 18,
                  ),
                  onPressed: _copy,
                  tooltip: _copied ? 'Copié !' : 'Copier',
                ),
            ],
          ),
        ),
      ],
    );
  }
}
