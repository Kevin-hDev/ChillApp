import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/extensions/chill_theme.dart';
import '../../shared/helpers/responsive.dart';
import '../../shared/widgets/animated_loader.dart';
import '../../shared/widgets/copyable_info.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/explanation_card.dart';
import '../../shared/widgets/chill_background.dart';
import '../../shared/widgets/patience_message.dart';
import 'tailscale_provider.dart';

class TailscaleScreen extends ConsumerWidget {
  const TailscaleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final tsState = ref.watch(tailscaleProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: ChillBackground(
        child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = responsivePadding(width);

          return Center(
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
                            t(locale, 'tailscale.title'),
                            style: theme.textTheme.headlineLarge,
                          ),
                        ),
                        if (tsState.status != TailscaleConnectionStatus.loading)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () =>
                                ref.read(tailscaleProvider.notifier).refreshStatus(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(locale, 'tailscale.intro'),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),

                    // Contenu selon l'état
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildContent(context, ref, tsState, locale, theme),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    ThemeData theme,
  ) {
    switch (tsState.status) {
      case TailscaleConnectionStatus.loading:
        return Center(child: CircularProgressIndicator(color: context.chillAccent));
      case TailscaleConnectionStatus.loggedOut:
        return _buildLoggedOut(context, ref, tsState, locale, theme);
      case TailscaleConnectionStatus.connected:
        return _buildConnected(context, ref, tsState, locale, theme);
      case TailscaleConnectionStatus.error:
        return _buildError(context, ref, tsState, locale, theme);
    }
  }

  Widget _buildLoggedOut(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExplanationCard(
          titleKey: 'tailscale.explanation.title',
          contentKey: 'tailscale.explanation.content',
          locale: locale,
        ),
        const SizedBox(height: 24),

        if (tsState.isLoggingIn) ...[
          AnimatedLoader(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.chillAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.chillAccent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(Icons.vpn_lock, color: context.chillAccent, size: 36),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PatienceMessage(
            text: t(locale, 'tailscale.login.waiting'),
            color: context.chillAccent,
          ),
        ] else
          Column(
            children: [
              // Bouton "Se connecter" (principal, rempli accent)
              ElevatedButton.icon(
                onPressed: () => ref.read(tailscaleProvider.notifier).login(),
                icon: const Icon(Icons.login),
                label: Text(
                  t(locale, 'tailscale.login.button'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              // Texte "Pas encore de compte ?"
              Text(
                t(locale, 'tailscale.signup.desc'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.chillTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              // Bouton "Créer un compte" (secondaire, outlined)
              OutlinedButton.icon(
                onPressed: () async {
                  // Ouvrir la page d'inscription Tailscale
                  if (Platform.isLinux) await Process.run('xdg-open', ['https://login.tailscale.com/start']);
                  if (Platform.isWindows) await Process.run('cmd', ['/c', 'start', 'https://login.tailscale.com/start']);
                  if (Platform.isMacOS) await Process.run('open', ['https://login.tailscale.com/start']);
                },
                icon: const Icon(Icons.person_add_outlined),
                label: Text(t(locale, 'tailscale.signup.button')),
              ),
            ],
          ),

        // Message d'erreur
        if (tsState.errorMessage != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: tsState.errorMessage!),
        ],
      ],
    );
  }

  Widget _buildConnected(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bannière verte "Connecté"
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: context.chillAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ChillRadius.xl),
            border: Border.all(color: context.chillAccent),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: context.chillAccent, size: 24),
              const SizedBox(width: 12),
              Text(
                t(locale, 'tailscale.connected.title'),
                style: theme.textTheme.titleMedium?.copyWith(color: context.chillAccent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Self info card
        _SelfInfoCard(
          locale: locale,
          hostname: tsState.selfHostname,
          ip: tsState.selfIp,
        ),
        const SizedBox(height: 24),

        // Titre "Appareils sur ton réseau"
        Text(
          t(locale, 'tailscale.connected.peersTitle'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),

        // Liste des peers
        if (tsState.peers.isEmpty)
          Text(
            t(locale, 'tailscale.connected.noPeers'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.chillTextSecondary,
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.chillBgElevated,
              borderRadius: BorderRadius.circular(ChillRadius.xl),
              border: Border.all(color: context.chillBorder),
            ),
            child: Column(
              children: tsState.peers.map((peer) {
                return _PeerTile(peer: peer);
              }).toList(),
            ),
          ),

        const SizedBox(height: 24),

        // Bouton déconnexion
        Center(
          child: TextButton.icon(
            onPressed: () => ref.read(tailscaleProvider.notifier).logout(),
            icon: Icon(Icons.logout, color: context.chillRed),
            label: Text(
              t(locale, 'tailscale.connected.logout'),
              style: TextStyle(color: context.chillRed),
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildError(
    BuildContext context, WidgetRef ref, TailscaleState tsState,
    String locale, ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.chillRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ChillRadius.xl),
            border: Border.all(color: context.chillRed.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: context.chillRed, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(locale, 'tailscale.error.title'),
                      style: theme.textTheme.titleMedium?.copyWith(color: context.chillRed),
                    ),
                  ),
                ],
              ),
              if (tsState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  tsState.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => ref.read(tailscaleProvider.notifier).retry(),
            icon: const Icon(Icons.refresh),
            label: Text(t(locale, 'tailscale.error.retry')),
          ),
        ),
      ],
    );
  }
}

/// Carte d'info personnelle (hostname + IP Tailscale)
class _SelfInfoCard extends StatelessWidget {
  final String locale;
  final String? hostname;
  final String? ip;

  const _SelfInfoCard({
    required this.locale,
    this.hostname,
    this.ip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.chillAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: context.chillAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(locale, 'tailscale.connected.selfTitle'),
            style: theme.textTheme.headlineSmall?.copyWith(color: context.chillAccent),
          ),
          const SizedBox(height: 16),
          if (hostname != null) ...[
            Text(t(locale, 'tailscale.connected.hostname'),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: hostname!, locale: locale),
            const SizedBox(height: 16),
          ],
          if (ip != null) ...[
            Text(t(locale, 'tailscale.connected.ip'),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            CopyableInfo(value: ip!, locale: locale),
          ],
        ],
      ),
    );
  }
}

/// Tuile d'un peer Tailscale
class _PeerTile extends StatelessWidget {
  final TailscalePeer peer;

  const _PeerTile({required this.peer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = 'fr'; // Default locale for peer tiles

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Pastille online/offline
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: peer.isOnline ? context.chillGreen : context.chillTextMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Hostname + OS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.hostname,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (peer.os.isNotEmpty)
                  Text(
                    peer.os,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.chillTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // IP copiable
          Flexible(child: CopyableInfo(value: peer.ipv4, compact: true, locale: locale)),
        ],
      ),
    );
  }
}
