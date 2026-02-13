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
    final secState = ref.watch(securityProvider);
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
                            if (!secState.isCheckingAll)
                              IconButton(
                                icon: Icon(Icons.refresh, color: context.chillAccent),
                                onPressed: () =>
                                    ref.read(securityProvider.notifier).checkAllStatuses(),
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

                        if (secState.isCheckingAll)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(color: context.chillAccent),
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
                          ..._buildToggles(context, ref, secState, locale, os),

                        // Section Scan (Linux: rkhunter, Windows: Defender)
                        if (!secState.isCheckingAll &&
                            (os == SupportedOS.linux || os == SupportedOS.windows))
                          _buildScanSection(context, ref, secState, locale, theme, os),

                        const SizedBox(height: 32),

                        // Séparateur
                        Divider(color: context.chillBorder),
                        const SizedBox(height: 24),

                        // Section Checkup
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
                            onPressed: secState.isCheckupRunning
                                ? null
                                : () => ref.read(securityProvider.notifier).runCheckup(),
                            icon: secState.isCheckupRunning
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
                              secState.isCheckupRunning
                                  ? t(locale, 'security.checkup.running')
                                  : t(locale, 'security.checkup.button'),
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
                        const SizedBox(height: 24),

                        // Résultats du checkup
                        if (secState.checkupResults != null)
                          _buildCheckupResults(context, secState, locale, theme),

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

  List<Widget> _buildToggles(
    BuildContext context,
    WidgetRef ref,
    SecurityState secState,
    String locale,
    SupportedOS os,
  ) {
    final notifier = ref.read(securityProvider.notifier);

    switch (os) {
      case SupportedOS.windows:
        return _buildWindowsToggles(context, secState, locale, notifier);
      case SupportedOS.linux:
        return _buildLinuxToggles(context, secState, locale, notifier);
      case SupportedOS.macos:
        return _buildMacToggles(context, secState, locale, notifier);
    }
  }

  List<Widget> _buildWindowsToggles(
    BuildContext context,
    SecurityState s,
    String locale,
    SecurityNotifier notifier,
  ) {
    return [
      _toggle(context, s, locale, notifier, 'win.firewall', Icons.shield, 'security.win.firewall'),
      _toggle(context, s, locale, notifier, 'win.rdp', Icons.desktop_windows, 'security.win.rdp'),
      _toggle(context, s, locale, notifier, 'win.smb1', Icons.folder_shared, 'security.win.smb1'),
      _toggle(context, s, locale, notifier, 'win.remoteRegistry', Icons.app_registration, 'security.win.remoteRegistry'),
      _toggle(context, s, locale, notifier, 'win.ransomware', Icons.lock_outline, 'security.win.ransomware'),
      _toggle(context, s, locale, notifier, 'win.audit', Icons.receipt_long, 'security.win.audit'),
      _toggle(context, s, locale, notifier, 'win.updates', Icons.update, 'security.win.updates'),
    ];
  }

  List<Widget> _buildLinuxToggles(
    BuildContext context,
    SecurityState s,
    String locale,
    SecurityNotifier notifier,
  ) {
    final ufwInstalled = s.installed['ufw'] ?? false;
    final f2bInstalled = s.installed['fail2ban'] ?? false;
    final rkhInstalled = s.installed['rkhunter'] ?? false;

    return [
      // UFW — peut nécessiter installation
      if (!ufwInstalled)
        SecurityToggleCard(
          title: t(locale, 'security.linux.firewall'),
          description: t(locale, 'security.linux.firewall.desc'),
          icon: Icons.shield,
          needsInstall: true,
          installLabel: t(locale, 'security.install'),
          isLoading: s.toggleLoading['ufw'] ?? false,
          onInstall: () => notifier.install('ufw'),
        )
      else
        _toggle(context, s, locale, notifier, 'linux.firewall', Icons.shield, 'security.linux.firewall'),

      _toggle(context, s, locale, notifier, 'linux.sysctl', Icons.settings_ethernet, 'security.linux.sysctl'),

      // Services inutiles
      ServicesToggleCard(
        title: t(locale, 'security.linux.services'),
        description: t(locale, 'security.linux.services.desc'),
        services: s.services,
        isLoading: s.isCheckingAll,
        loadingServices: s.loadingServices,
        onToggleService: (name) => notifier.toggleService(name),
      ),

      _toggle(context, s, locale, notifier, 'linux.permissions', Icons.folder_special, 'security.linux.permissions'),

      // Fail2Ban — peut nécessiter installation
      if (!f2bInstalled)
        SecurityToggleCard(
          title: t(locale, 'security.linux.fail2ban'),
          description: t(locale, 'security.linux.fail2ban.desc'),
          icon: Icons.block,
          needsInstall: true,
          installLabel: t(locale, 'security.install'),
          isLoading: s.toggleLoading['fail2ban'] ?? false,
          onInstall: () => notifier.install('fail2ban'),
        )
      else
        _toggle(context, s, locale, notifier, 'linux.fail2ban', Icons.block, 'security.linux.fail2ban'),

      _toggle(context, s, locale, notifier, 'linux.updates', Icons.update, 'security.linux.updates'),
      _toggle(context, s, locale, notifier, 'linux.rootLogin', Icons.person_off, 'security.linux.rootLogin'),

      // rkhunter — peut nécessiter installation
      if (!rkhInstalled)
        SecurityToggleCard(
          title: t(locale, 'security.linux.rkhunter'),
          description: t(locale, 'security.linux.rkhunter.desc'),
          icon: Icons.bug_report,
          needsInstall: true,
          installLabel: t(locale, 'security.install'),
          isLoading: s.toggleLoading['rkhunter'] ?? false,
          onInstall: () => notifier.install('rkhunter'),
        )
      else
        SecurityToggleCard(
          title: t(locale, 'security.linux.rkhunter'),
          description: t(locale, 'security.linux.rkhunter.desc'),
          icon: Icons.bug_report,
          isEnabled: true, // Installé = OK, le scan se fait dans le checkup
        ),
    ];
  }

  List<Widget> _buildMacToggles(
    BuildContext context,
    SecurityState s,
    String locale,
    SecurityNotifier notifier,
  ) {
    return [
      _toggle(context, s, locale, notifier, 'mac.firewall', Icons.shield, 'security.mac.firewall'),
      _toggle(context, s, locale, notifier, 'mac.stealth', Icons.visibility_off, 'security.mac.stealth'),
      _toggle(context, s, locale, notifier, 'mac.smb', Icons.folder_shared, 'security.mac.smb'),
      _toggle(context, s, locale, notifier, 'mac.updates', Icons.update, 'security.mac.updates'),
      _toggle(context, s, locale, notifier, 'mac.secureKeyboard', Icons.keyboard, 'security.mac.secureKeyboard'),
      _toggle(context, s, locale, notifier, 'mac.gatekeeper', Icons.verified_user, 'security.mac.gatekeeper'),
      _toggle(context, s, locale, notifier, 'mac.screenLock', Icons.lock_clock, 'security.mac.screenLock'),
    ];
  }

  /// Helper pour construire un SecurityToggleCard standard
  Widget _toggle(
    BuildContext context,
    SecurityState s,
    String locale,
    SecurityNotifier notifier,
    String id,
    IconData icon,
    String i18nKey,
  ) {
    return SecurityToggleCard(
      title: t(locale, i18nKey),
      description: t(locale, '$i18nKey.desc'),
      icon: icon,
      isEnabled: s.toggleStates[id],
      isLoading: s.toggleLoading[id] ?? false,
      onToggle: (enable) => notifier.toggle(id, enable),
    );
  }

  /// Affiche les résultats du checkup
  Widget _buildCheckupResults(
    BuildContext context,
    SecurityState secState,
    String locale,
    ThemeData theme,
  ) {
    final results = secState.checkupResults!;
    final score = secState.checkupScore ?? 0;

    // Vérifier si un check critique ou haut est en erreur
    final hasCriticalError = results.any((item) =>
        item.severity == CheckSeverity.critical &&
        item.status == CheckupStatus.error);
    final hasHighError = results.any((item) =>
        item.severity == CheckSeverity.high &&
        item.status == CheckupStatus.error);

    // Couleur et label selon le score ET la criticité
    Color scoreColor;
    String scoreLabel;
    if (hasCriticalError) {
      // Un check CRITIQUE est en erreur → rouge, peu importe le score
      scoreColor = context.chillRed;
      scoreLabel = t(locale, 'security.checkup.critical');
    } else if (hasHighError) {
      // Un check HAUT est en erreur → orange
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
          ...results.map((item) => _buildCheckupItem(context, item, locale, theme)),
        ],
      ),
    );
  }

  /// Section d'analyse (rkhunter / Defender)
  Widget _buildScanSection(
    BuildContext context,
    WidgetRef ref,
    SecurityState secState,
    String locale,
    ThemeData theme,
    SupportedOS os,
  ) {
    // Sur Linux, ne montrer que si rkhunter est installé
    if (os == SupportedOS.linux && !(secState.installed['rkhunter'] ?? false)) {
      return const SizedBox.shrink();
    }

    final notifier = ref.read(securityProvider.notifier);

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
          t(locale, os == SupportedOS.windows
              ? 'security.scan.desc.windows'
              : 'security.scan.desc.linux'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.chillTextSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Bouton
        Center(
          child: ElevatedButton.icon(
            onPressed: secState.isScanRunning
                ? null
                : () => notifier.runScan(),
            icon: secState.isScanRunning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.chillAccent,
                    ),
                  )
                : Icon(os == SupportedOS.windows
                    ? Icons.shield
                    : Icons.search),
            label: Text(
              secState.isScanRunning
                  ? t(locale, 'security.scan.running')
                  : t(locale, 'security.scan.button'),
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
        if (secState.isScanRunning) ...[
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
        if (secState.scanWarnings != null)
          _buildScanResults(context, secState.scanWarnings!, locale, theme),
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
          color: isClean ? context.chillGreen.withValues(alpha: 0.3) : context.chillOrange.withValues(alpha: 0.3),
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
                      : t(locale, 'security.scan.warnings')
                          .replaceAll('{count}', '${warnings.length}'),
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
            ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_right,
                          color: context.chillTextMuted, size: 18),
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
                )),
          ],
        ],
      ),
    );
  }

  /// Traduit un code de détail du checkup en texte localisé.
  /// Ex: "active" → "Actif", "pct:65" → "65% utilisé"
  String _localizeDetail(String id, String rawDetail, String locale) {
    final colonIndex = rawDetail.indexOf(':');
    final code = colonIndex >= 0 ? rawDetail.substring(0, colonIndex) : rawDetail;
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
