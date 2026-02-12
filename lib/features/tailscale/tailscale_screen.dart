import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import 'tailscale_provider.dart';

class TailscaleScreen extends ConsumerWidget {
  const TailscaleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final tsState = ref.watch(tailscaleProvider);
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
                    child: _buildContent(
                      context,
                      ref,
                      tsState,
                      locale,
                      isDark,
                      accent,
                      theme,
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

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    bool isDark,
    Color accent,
    ThemeData theme,
  ) {
    switch (tsState.status) {
      case TailscaleConnectionStatus.loading:
        return Center(child: CircularProgressIndicator(color: accent));
      case TailscaleConnectionStatus.loggedOut:
        return _buildLoggedOut(context, ref, tsState, locale, isDark, accent, theme);
      case TailscaleConnectionStatus.connected:
        return _buildConnected(context, ref, tsState, locale, isDark, accent, theme);
      case TailscaleConnectionStatus.error:
        return _buildError(context, ref, tsState, locale, isDark, accent, theme);
    }
  }

  Widget _buildLoggedOut(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    bool isDark,
    Color accent,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExplanationCard(locale: locale, isDark: isDark),
        const SizedBox(height: 24),

        if (tsState.isLoggingIn) ...[
          const _AnimatedLoader(),
          const SizedBox(height: 12),
          _PatienceMessage(locale: locale, accent: accent),
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
                  color: isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary,
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
                    tsState.errorMessage!,
                    style: TextStyle(
                      color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnected(
    BuildContext context,
    WidgetRef ref,
    TailscaleState tsState,
    String locale,
    bool isDark,
    Color accent,
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
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ChillRadius.xl),
            border: Border.all(color: accent),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: accent, size: 24),
              const SizedBox(width: 12),
              Text(
                t(locale, 'tailscale.connected.title'),
                style: theme.textTheme.titleMedium?.copyWith(color: accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Self info card
        _SelfInfoCard(
          locale: locale,
          isDark: isDark,
          accent: accent,
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
              color: isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary,
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? ChillColorsDark.bgElevated : ChillColorsLight.bgElevated,
              borderRadius: BorderRadius.circular(ChillRadius.xl),
              border: Border.all(
                color: isDark ? ChillColorsDark.border : ChillColorsLight.border,
              ),
            ),
            child: Column(
              children: tsState.peers.map((peer) {
                return _PeerTile(peer: peer, isDark: isDark);
              }).toList(),
            ),
          ),

        const SizedBox(height: 24),

        // Bouton déconnexion
        Center(
          child: TextButton.icon(
            onPressed: () => ref.read(tailscaleProvider.notifier).logout(),
            icon: Icon(Icons.logout, color: isDark ? ChillColorsDark.red : ChillColorsLight.red),
            label: Text(
              t(locale, 'tailscale.connected.logout'),
              style: TextStyle(
                color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildError(
    BuildContext context, WidgetRef ref, TailscaleState tsState,
    String locale, bool isDark, Color accent, ThemeData theme,
  ) {
    final red = isDark ? ChillColorsDark.red : ChillColorsLight.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ChillRadius.xl),
            border: Border.all(color: red.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(locale, 'tailscale.error.title'),
                      style: theme.textTheme.titleMedium?.copyWith(color: red),
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

/// Carte explicative "Qu'est-ce que Tailscale ?"
class _ExplanationCard extends StatelessWidget {
  final String locale;
  final bool isDark;

  const _ExplanationCard({required this.locale, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? ChillColorsDark.bgElevated : ChillColorsLight.bgElevated,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(
          color: isDark ? ChillColorsDark.border : ChillColorsLight.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: accent, size: 22),
              const SizedBox(width: 10),
              Text(
                t(locale, 'tailscale.explanation.title'),
                style: theme.textTheme.titleMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t(locale, 'tailscale.explanation.content'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// Carte d'info personnelle (hostname + IP Tailscale)
class _SelfInfoCard extends StatelessWidget {
  final String locale;
  final bool isDark;
  final Color accent;
  final String? hostname;
  final String? ip;

  const _SelfInfoCard({
    required this.locale,
    required this.isDark,
    required this.accent,
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
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(locale, 'tailscale.connected.selfTitle'),
            style: theme.textTheme.headlineSmall?.copyWith(color: accent),
          ),
          const SizedBox(height: 16),
          if (hostname != null) ...[
            Text(t(locale, 'tailscale.connected.hostname'),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            _CopyableInfo(value: hostname!, isDark: isDark),
            const SizedBox(height: 16),
          ],
          if (ip != null) ...[
            Text(t(locale, 'tailscale.connected.ip'),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            _CopyableInfo(value: ip!, isDark: isDark),
          ],
        ],
      ),
    );
  }
}

/// Tuile d'un peer Tailscale
class _PeerTile extends StatelessWidget {
  final TailscalePeer peer;
  final bool isDark;

  const _PeerTile({required this.peer, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Pastille online/offline
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: peer.isOnline
                  ? (isDark ? ChillColorsDark.green : ChillColorsLight.green)
                  : (isDark ? ChillColorsDark.textMuted : ChillColorsLight.textMuted),
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
                      color: isDark
                          ? ChillColorsDark.textSecondary
                          : ChillColorsLight.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // IP copiable
          _CopyableIp(ip: peer.ipv4, isDark: isDark),
        ],
      ),
    );
  }
}

/// IP copiable compacte pour les peers
class _CopyableIp extends StatefulWidget {
  final String ip;
  final bool isDark;

  const _CopyableIp({required this.ip, required this.isDark});

  @override
  State<_CopyableIp> createState() => _CopyableIpState();
}

class _CopyableIpState extends State<_CopyableIp> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.ip));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.ip,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: widget.isDark ? ChillColorsDark.textPrimary : ChillColorsLight.textPrimary,
          ),
        ),
        IconButton(
          icon: Icon(
            _copied ? Icons.check : Icons.copy,
            color: _copied
                ? accent
                : (widget.isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary),
            size: 16,
          ),
          onPressed: _copy,
          tooltip: _copied ? 'Copié !' : 'Copier',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

/// Ligne d'info avec bouton copier
class _CopyableInfo extends StatefulWidget {
  final String value;
  final bool isDark;

  const _CopyableInfo({required this.value, required this.isDark});

  @override
  State<_CopyableInfo> createState() => _CopyableInfoState();
}

class _CopyableInfoState extends State<_CopyableInfo> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Container(
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
              widget.value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: widget.isDark ? ChillColorsDark.textPrimary : ChillColorsLight.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              color: _copied ? accent : (widget.isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary),
              size: 18,
            ),
            onPressed: _copy,
            tooltip: _copied ? 'Copié !' : 'Copier',
          ),
        ],
      ),
    );
  }
}

/// Loader animé avec icône vpn_lock
class _AnimatedLoader extends StatefulWidget {
  const _AnimatedLoader();

  @override
  State<_AnimatedLoader> createState() => _AnimatedLoaderState();
}

class _AnimatedLoaderState extends State<_AnimatedLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Center(
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.3), width: 2),
              ),
              child: Center(
                child: Icon(Icons.vpn_lock, color: accent, size: 36),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Message "En attente de connexion..." avec animation fade
class _PatienceMessage extends StatefulWidget {
  final String locale;
  final Color accent;

  const _PatienceMessage({required this.locale, required this.accent});

  @override
  State<_PatienceMessage> createState() => _PatienceMessageState();
}

class _PatienceMessageState extends State<_PatienceMessage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Text(
          t(widget.locale, 'tailscale.login.waiting'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.accent,
          ),
        ),
      ),
    );
  }
}
