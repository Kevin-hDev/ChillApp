import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/design_tokens.dart';
import '../../core/os_detector.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/extensions/chill_theme.dart';
import '../../shared/helpers/responsive.dart';
import '../../shared/widgets/chill_background.dart';
import 'security_provider.dart';
import 'widgets/security_toggle_card.dart';
import 'widgets/services_toggle_card.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isCheckingAll = ref.watch(
      securityProvider.select((s) => s.isCheckingAll),
    );
    final theme = Theme.of(context);
    final os = OsDetector.currentOS;

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
                        // Header
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
                                t(locale, 'security.title'),
                                style: theme.textTheme.headlineLarge,
                              ),
                            ),
                            // Bouton rafraîchir
                            if (!isCheckingAll)
                              IconButton(
                                icon: Icon(
                                  Icons.refresh,
                                  color: context.chillAccent,
                                ),
                                onPressed: () => ref
                                    .read(securityProvider.notifier)
                                    .checkAllStatuses(force: true),
                                tooltip: t(locale, 'info.refresh'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(locale, 'security.intro'),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),

                        // Section Protections
                        Text(
                          t(locale, 'security.toggles.title'),
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),

                        if (isCheckingAll)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                    color: context.chillAccent,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    t(locale, 'security.checking'),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: context.chillTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._buildToggleWidgets(os),

                        // Section Scan (Linux: rkhunter, Windows: Defender)
                        if (!isCheckingAll &&
                            (os == SupportedOS.linux ||
                                os == SupportedOS.windows))
                          _ScanSection(os: os),

                        const SizedBox(height: 32),

                        // Séparateur
                        Divider(color: context.chillBorder),
                        const SizedBox(height: 24),

                        // Section Checkup
                        const _CheckupSection(),

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

  /// Retourne la liste de widgets toggles selon l'OS.
  /// Chaque toggle est un ConsumerWidget autonome qui ne rebuild
  /// que quand son propre état change.
  List<Widget> _buildToggleWidgets(SupportedOS os) {
    switch (os) {
      case SupportedOS.windows:
        return const [
          _ToggleItem(
            id: 'win.firewall',
            icon: Icons.shield,
            i18nKey: 'security.win.firewall',
          ),
          _ToggleItem(
            id: 'win.rdp',
            icon: Icons.desktop_windows,
            i18nKey: 'security.win.rdp',
          ),
          _ToggleItem(
            id: 'win.smb1',
            icon: Icons.folder_shared,
            i18nKey: 'security.win.smb1',
          ),
          _ToggleItem(
            id: 'win.remoteRegistry',
            icon: Icons.app_registration,
            i18nKey: 'security.win.remoteRegistry',
          ),
          _ToggleItem(
            id: 'win.ransomware',
            icon: Icons.lock_outline,
            i18nKey: 'security.win.ransomware',
          ),
          _ToggleItem(
            id: 'win.audit',
            icon: Icons.receipt_long,
            i18nKey: 'security.win.audit',
          ),
          _ToggleItem(
            id: 'win.updates',
            icon: Icons.update,
            i18nKey: 'security.win.updates',
          ),
          _ToggleItem(
            id: 'win.lsa',
            icon: Icons.security,
            i18nKey: 'security.win.lsa',
            needsReboot: true,
          ),
          _ToggleItem(
            id: 'win.hvci',
            icon: Icons.memory,
            i18nKey: 'security.win.hvci',
            needsReboot: true,
          ),
          _ToggleItem(id: 'win.dns', icon: Icons.dns, i18nKey: 'security.dns'),
        ];
      case SupportedOS.linux:
        return const [
          _InstallableToggle(
            toolId: 'ufw',
            toggleId: 'linux.firewall',
            icon: Icons.shield,
            i18nKey: 'security.linux.firewall',
          ),
          _ToggleItem(
            id: 'linux.sysctl',
            icon: Icons.settings_ethernet,
            i18nKey: 'security.linux.sysctl',
          ),
          _ServicesSection(),
          _StatusOnlyToggle(
            id: 'linux.permissions',
            icon: Icons.folder_special,
            i18nKey: 'security.linux.permissions',
          ),
          _InstallableToggle(
            toolId: 'fail2ban',
            toggleId: 'linux.fail2ban',
            icon: Icons.block,
            i18nKey: 'security.linux.fail2ban',
          ),
          _InstallableToggle(
            toolId: 'crowdsec',
            toggleId: 'linux.crowdsec',
            icon: Icons.groups,
            i18nKey: 'security.linux.crowdsec',
          ),
          _ToggleItem(
            id: 'linux.apparmor',
            icon: Icons.verified_user,
            i18nKey: 'security.linux.apparmor',
          ),
          _ToggleItem(
            id: 'linux.updates',
            icon: Icons.update,
            i18nKey: 'security.linux.updates',
          ),
          _ToggleItem(
            id: 'linux.rootLogin',
            icon: Icons.person_off,
            i18nKey: 'security.linux.rootLogin',
          ),
          _ToggleItem(
            id: 'linux.dns',
            icon: Icons.dns,
            i18nKey: 'security.dns',
          ),
          _InstallableToggle(
            toolId: 'rkhunter',
            icon: Icons.bug_report,
            i18nKey: 'security.linux.rkhunter',
          ),
        ];
      case SupportedOS.macos:
        return const [
          _ToggleItem(
            id: 'mac.firewall',
            icon: Icons.shield,
            i18nKey: 'security.mac.firewall',
          ),
          _ToggleItem(
            id: 'mac.stealth',
            icon: Icons.visibility_off,
            i18nKey: 'security.mac.stealth',
          ),
          _ToggleItem(
            id: 'mac.smb',
            icon: Icons.folder_shared,
            i18nKey: 'security.mac.smb',
          ),
          _ToggleItem(
            id: 'mac.updates',
            icon: Icons.update,
            i18nKey: 'security.mac.updates',
          ),
          _ToggleItem(
            id: 'mac.secureKeyboard',
            icon: Icons.keyboard,
            i18nKey: 'security.mac.secureKeyboard',
          ),
          _ToggleItem(
            id: 'mac.gatekeeper',
            icon: Icons.verified_user,
            i18nKey: 'security.mac.gatekeeper',
          ),
          _ToggleItem(
            id: 'mac.screenLock',
            icon: Icons.lock_clock,
            i18nKey: 'security.mac.screenLock',
          ),
          _ToggleItem(id: 'mac.dns', icon: Icons.dns, i18nKey: 'security.dns'),
        ];
    }
  }
}

/// Widget autonome pour un toggle de sécurité standard.
/// Ne rebuild que quand l'état de CE toggle change.
class _ToggleItem extends ConsumerWidget {
  final String id;
  final IconData icon;
  final String i18nKey;
  final bool needsReboot;

  const _ToggleItem({
    required this.id,
    required this.icon,
    required this.i18nKey,
    this.needsReboot = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isEnabled = ref.watch(
      securityProvider.select((s) => s.toggleStates[id]),
    );
    final isLoading = ref.watch(
      securityProvider.select((s) => s.toggleLoading[id] ?? false),
    );

    return SecurityToggleCard(
      title: t(locale, i18nKey),
      description: t(locale, '$i18nKey.desc'),
      icon: icon,
      isEnabled: isEnabled,
      isLoading: isLoading,
      onToggle: (enable) async {
        await ref.read(securityProvider.notifier).toggle(id, enable);
        if (needsReboot && enable && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              backgroundColor: context.chillBgElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ChillRadius.lg),
                side: BorderSide(color: context.chillBorder),
              ),
              duration: const Duration(seconds: 5),
              content: Row(
                children: [
                  Icon(Icons.restart_alt, color: context.chillAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t(locale, 'security.reboot.message'),
                      style: TextStyle(
                        color: context.chillTextPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

/// Widget pour un toggle qui peut nécessiter une installation (ufw, fail2ban, rkhunter).
/// toggleId null = status-only après installation (rkhunter).
class _InstallableToggle extends ConsumerWidget {
  final String toolId;
  final String? toggleId;
  final IconData icon;
  final String i18nKey;

  const _InstallableToggle({
    required this.toolId,
    this.toggleId,
    required this.icon,
    required this.i18nKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isInstalled = ref.watch(
      securityProvider.select((s) => s.installed[toolId] ?? false),
    );

    if (!isInstalled) {
      final isLoading = ref.watch(
        securityProvider.select((s) => s.toggleLoading[toolId] ?? false),
      );
      return SecurityToggleCard(
        title: t(locale, i18nKey),
        description: t(locale, '$i18nKey.desc'),
        icon: icon,
        needsInstall: true,
        installLabel: t(locale, 'security.install'),
        isLoading: isLoading,
        onInstall: () => ref.read(securityProvider.notifier).install(toolId),
      );
    }

    if (toggleId != null) {
      final isEnabled = ref.watch(
        securityProvider.select((s) => s.toggleStates[toggleId]),
      );
      final isLoading = ref.watch(
        securityProvider.select((s) => s.toggleLoading[toggleId] ?? false),
      );
      return SecurityToggleCard(
        title: t(locale, i18nKey),
        description: t(locale, '$i18nKey.desc'),
        icon: icon,
        isEnabled: isEnabled,
        isLoading: isLoading,
        onToggle: (enable) =>
            ref.read(securityProvider.notifier).toggle(toggleId!, enable),
      );
    }

    // Status-only (rkhunter installé = OK)
    return SecurityToggleCard(
      title: t(locale, i18nKey),
      description: t(locale, '$i18nKey.desc'),
      icon: icon,
      isEnabled: true,
    );
  }
}

/// Widget pour un toggle à sens unique (peut activer, pas désactiver).
/// Affiche un checkmark quand activé, un bouton quand désactivé.
class _StatusOnlyToggle extends ConsumerWidget {
  final String id;
  final IconData icon;
  final String i18nKey;

  const _StatusOnlyToggle({
    required this.id,
    required this.icon,
    required this.i18nKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isEnabled = ref.watch(
      securityProvider.select((s) => s.toggleStates[id]),
    );
    final isLoading = ref.watch(
      securityProvider.select((s) => s.toggleLoading[id] ?? false),
    );

    return SecurityToggleCard(
      title: t(locale, i18nKey),
      description: t(locale, '$i18nKey.desc'),
      icon: icon,
      isEnabled: isEnabled,
      isLoading: isLoading,
      // Permet d'activer uniquement — si déjà actif, pas de onToggle (affiche checkmark)
      onToggle: isEnabled == true
          ? null
          : (enable) => ref.read(securityProvider.notifier).toggle(id, true),
    );
  }
}

/// Section Services Linux — rebuild uniquement quand services/loadingServices changent
class _ServicesSection extends ConsumerWidget {
  const _ServicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final services = ref.watch(securityProvider.select((s) => s.services));
    final isCheckingAll = ref.watch(
      securityProvider.select((s) => s.isCheckingAll),
    );
    final loadingServices = ref.watch(
      securityProvider.select((s) => s.loadingServices),
    );

    return ServicesToggleCard(
      title: t(locale, 'security.linux.services'),
      description: t(locale, 'security.linux.services.desc'),
      services: services,
      isLoading: isCheckingAll,
      loadingServices: loadingServices,
      onToggleService: (name) =>
          ref.read(securityProvider.notifier).toggleService(name),
    );
  }
}

/// Section Scan (rkhunter / Defender) — rebuild uniquement quand scan change
class _ScanSection extends ConsumerWidget {
  final SupportedOS os;

  const _ScanSection({required this.os});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isScanRunning = ref.watch(
      securityProvider.select((s) => s.isScanRunning),
    );
    final scanWarnings = ref.watch(
      securityProvider.select((s) => s.scanWarnings),
    );
    final theme = Theme.of(context);

    // Linux : ne montrer que si rkhunter est installé
    if (os == SupportedOS.linux) {
      final rkhInstalled = ref.watch(
        securityProvider.select((s) => s.installed['rkhunter'] ?? false),
      );
      if (!rkhInstalled) return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Divider(color: context.chillBorder),
        const SizedBox(height: 24),

        // Titre
        Row(
          children: [
            Icon(
              os == SupportedOS.windows ? Icons.shield : Icons.bug_report,
              color: context.chillAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              t(locale, 'security.scan.title'),
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          t(
            locale,
            os == SupportedOS.windows
                ? 'security.scan.desc.windows'
                : 'security.scan.desc.linux',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.chillTextSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Bouton
        Center(
          child: ElevatedButton.icon(
            onPressed: isScanRunning
                ? null
                : () => ref.read(securityProvider.notifier).runScan(),
            icon: isScanRunning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.chillAccent,
                    ),
                  )
                : Icon(os == SupportedOS.windows ? Icons.shield : Icons.search),
            label: Text(
              isScanRunning
                  ? t(locale, 'security.scan.running')
                  : t(locale, 'security.scan.button'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ),
        if (isScanRunning) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              t(locale, 'security.scan.patience'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.chillTextMuted,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Résultats
        if (scanWarnings != null)
          _buildScanResults(context, scanWarnings, locale, theme),
      ],
    );
  }

  Widget _buildScanResults(
    BuildContext context,
    List<String> warnings,
    String locale,
    ThemeData theme,
  ) {
    final isClean = warnings.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.chillBgElevated,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(
          color: isClean
              ? context.chillGreen.withValues(alpha: 0.3)
              : context.chillOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isClean ? Icons.check_circle : Icons.warning_amber_rounded,
                color: isClean ? context.chillGreen : context.chillOrange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isClean
                      ? t(locale, 'security.scan.clean')
                      : t(
                          locale,
                          'security.scan.warnings',
                        ).replaceAll('{count}', '${warnings.length}'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isClean ? context.chillGreen : context.chillOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (!isClean) ...[
            const SizedBox(height: 12),
            ...warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.arrow_right,
                      color: context.chillTextMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        w,
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
        ],
      ),
    );
  }
}

/// Section Checkup — rebuild uniquement quand checkup change
class _CheckupSection extends ConsumerWidget {
  const _CheckupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isCheckupRunning = ref.watch(
      securityProvider.select((s) => s.isCheckupRunning),
    );
    final checkupResults = ref.watch(
      securityProvider.select((s) => s.checkupResults),
    );
    final checkupScore = ref.watch(
      securityProvider.select((s) => s.checkupScore),
    );
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titre
        Text(
          t(locale, 'security.checkup.title'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          t(locale, 'security.checkup.desc'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.chillTextSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Bouton Checkup
        Center(
          child: ElevatedButton.icon(
            onPressed: isCheckupRunning
                ? null
                : () => ref.read(securityProvider.notifier).runCheckup(),
            icon: isCheckupRunning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.chillAccent,
                    ),
                  )
                : const Icon(Icons.health_and_safety),
            label: Text(
              isCheckupRunning
                  ? t(locale, 'security.checkup.running')
                  : t(locale, 'security.checkup.button'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Résultats du checkup
        if (checkupResults != null)
          _buildCheckupResults(
            context,
            checkupResults,
            checkupScore ?? 0,
            locale,
            theme,
          ),
      ],
    );
  }

  /// Affiche les résultats du checkup
  Widget _buildCheckupResults(
    BuildContext context,
    List<CheckupItem> results,
    double score,
    String locale,
    ThemeData theme,
  ) {
    // Vérifier si un check critique ou haut est en erreur
    final hasCriticalError = results.any(
      (item) =>
          item.severity == CheckSeverity.critical &&
          item.status == CheckupStatus.error,
    );
    final hasHighError = results.any(
      (item) =>
          item.severity == CheckSeverity.high &&
          item.status == CheckupStatus.error,
    );

    // Couleur et label selon le score ET la criticité
    Color scoreColor;
    String scoreLabel;
    if (hasCriticalError) {
      scoreColor = context.chillRed;
      scoreLabel = t(locale, 'security.checkup.critical');
    } else if (hasHighError) {
      scoreColor = context.chillOrange;
      scoreLabel = t(locale, 'security.checkup.medium');
    } else if (score >= 0.85) {
      scoreColor = context.chillGreen;
      scoreLabel = t(locale, 'security.checkup.excellent');
    } else if (score >= 0.65) {
      scoreColor = context.chillOrange;
      scoreLabel = t(locale, 'security.checkup.good');
    } else {
      scoreColor = context.chillRed;
      scoreLabel = t(locale, 'security.checkup.critical');
    }

    final scorePercent = (score * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.chillBgElevated,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: context.chillBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score global
          Row(
            children: [
              Icon(Icons.health_and_safety, color: scoreColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t(locale, 'security.checkup.score')} : $scorePercent%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scoreColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      scoreLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.chillTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Barre de progression
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score,
              backgroundColor: context.chillBgSurface,
              color: scoreColor,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 20),

          // Liste des résultats
          ...results.map(
            (item) => _buildCheckupItem(context, item, locale, theme),
          ),
        ],
      ),
    );
  }

  /// Traduit un code de détail du checkup en texte localisé.
  String _localizeDetail(String id, String rawDetail, String locale) {
    final colonIndex = rawDetail.indexOf(':');
    final code = colonIndex >= 0
        ? rawDetail.substring(0, colonIndex)
        : rawDetail;
    final value = colonIndex >= 0 ? rawDetail.substring(colonIndex + 1) : '';

    final key = 'security.detail.$id.$code';
    final translated = t(locale, key);
    if (translated != key) {
      return translated.replaceAll('{value}', value);
    }
    return rawDetail;
  }

  Widget _buildCheckupItem(
    BuildContext context,
    CheckupItem item,
    String locale,
    ThemeData theme,
  ) {
    IconData icon;
    Color color;
    switch (item.status) {
      case CheckupStatus.ok:
        icon = Icons.check_circle;
        color = context.chillGreen;
        break;
      case CheckupStatus.warning:
        icon = Icons.warning_amber_rounded;
        color = context.chillOrange;
        break;
      case CheckupStatus.error:
        icon = Icons.cancel;
        color = context.chillRed;
        break;
    }

    // Label du checkup item
    final labelKey = 'security.checkup.${item.id}';
    final label = t(locale, labelKey);

    // Badge de sévérité (affiché seulement si warning ou error)
    final severityKey = 'security.severity.${item.severity.name}';
    final severityLabel = t(locale, severityKey);
    Color severityColor;
    switch (item.severity) {
      case CheckSeverity.critical:
        severityColor = context.chillRed;
        break;
      case CheckSeverity.high:
        severityColor = context.chillOrange;
        break;
      case CheckSeverity.medium:
        severityColor = context.chillTextSecondary;
        break;
      case CheckSeverity.minor:
        severityColor = context.chillTextMuted;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.status != CheckupStatus.ok) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: severityColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          severityLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: severityColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  _localizeDetail(item.id, item.detail, locale),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.chillTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
