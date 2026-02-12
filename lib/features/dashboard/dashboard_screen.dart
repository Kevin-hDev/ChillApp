import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/widgets/chill_card.dart';
import '../../shared/widgets/status_badge.dart';
import 'dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final dashboard = ref.watch(dashboardProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = width < 600 ? 16.0 : width < 900 ? 24.0 : 32.0;
          final columns = width < 600 ? 2 : width < 1000 ? 3 : 3;
          final topSpacing = width < 600 ? 24.0 : 48.0;

          // Calculer la hauteur disponible pour la grille
          final height = constraints.maxHeight;
          final headerHeight = topSpacing + 40 + 8 + 20 + topSpacing; // titre + desc + espacement
          final gridHeight = height - headerHeight - padding * 2;
          final rows = (6 / columns).ceil();
          final totalSpacing = (rows - 1) * 16.0;
          final cardHeight = (gridHeight - totalSpacing) / rows;
          final gridWidth = width - padding * 2;
          final totalHSpacing = (columns - 1) * 16.0;
          final cardWidth = (gridWidth - totalHSpacing) / columns;
          final aspectRatio = cardWidth / cardHeight;

          return Center(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: topSpacing),
                  Text(
                    t(locale, 'dashboard.welcome'),
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(locale, 'dashboard.description'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  SizedBox(height: topSpacing),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: aspectRatio.clamp(0.5, 3.0),
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                      ChillCard(
                        icon: Icons.terminal,
                        title: t(locale, 'dashboard.ssh.title'),
                        description: t(locale, 'dashboard.ssh.desc'),
                        onTap: () => context.go('/ssh'),
                        badge: dashboard.sshConfigured != null
                            ? StatusBadge(
                                label: dashboard.sshConfigured!
                                    ? t(locale, 'status.configured')
                                    : t(locale, 'status.notConfigured'),
                                isConfigured: dashboard.sshConfigured!,
                              )
                            : null,
                      ),
                      ChillCard(
                        icon: Icons.power_settings_new,
                        title: t(locale, 'dashboard.wol.title'),
                        description: t(locale, 'dashboard.wol.desc'),
                        onTap: () => context.go('/wol'),
                        badge: dashboard.wolConfigured != null
                            ? StatusBadge(
                                label: dashboard.wolConfigured!
                                    ? t(locale, 'status.configured')
                                    : t(locale, 'status.notConfigured'),
                                isConfigured: dashboard.wolConfigured!,
                              )
                            : null,
                      ),
                      ChillCard(
                        icon: Icons.vpn_lock,
                        title: t(locale, 'dashboard.tailscale.title'),
                        description: t(locale, 'dashboard.tailscale.desc'),
                        onTap: () => context.go('/tailscale'),
                        badge: dashboard.tailscaleConnected != null
                            ? StatusBadge(
                                label: dashboard.tailscaleConnected!
                                    ? t(locale, 'status.connected')
                                    : t(locale, 'status.notConnected'),
                                isConfigured: dashboard.tailscaleConnected!,
                              )
                            : null,
                      ),
                      ChillCard(
                        icon: Icons.info_outline,
                        title: t(locale, 'dashboard.info.title'),
                        description: t(locale, 'dashboard.info.desc'),
                        onTap: () => context.go('/info'),
                      ),
                      ChillCard(
                        icon: Icons.settings,
                        title: t(locale, 'nav.settings'),
                        description: '',
                        onTap: () => context.go('/settings'),
                      ),
                      // Mascotte
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/images/mascot.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
