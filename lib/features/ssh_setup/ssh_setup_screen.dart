import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/widgets/step_indicator.dart';
import 'ssh_setup_provider.dart';

class SshSetupScreen extends ConsumerWidget {
  const SshSetupScreen({super.key});

  /// Convertit un ID d'étape en clé de traduction
  String _stepLabel(String locale, String stepId) {
    final key = 'ssh.step.$stepId';
    return t(locale, key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final sshState = ref.watch(sshSetupProvider);
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

                // Contenu scrollable
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Carte explicative
                        _ExplanationCard(locale: locale, isDark: isDark),
                        const SizedBox(height: 24),

                        // Bouton "Tout configurer" ou "Réessayer"
                        if (!sshState.isRunning && !sshState.isComplete)
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () => ref.read(sshSetupProvider.notifier).runAll(),
                              icon: Icon(
                                sshState.errorMessage != null ? Icons.refresh : Icons.play_arrow,
                              ),
                              label: Text(
                                sshState.errorMessage != null
                                    ? t(locale, 'ssh.error.retry')
                                    : t(locale, 'ssh.configureAll'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              ),
                            ),
                          ),

                        // Message d'erreur global
                        if (sshState.errorMessage != null && !sshState.isRunning) ...[
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
                                    sshState.errorMessage!,
                                    style: TextStyle(
                                      color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Loader animé + message de patience
                        if (sshState.isRunning) ...[
                          const _AnimatedLoader(),
                          const SizedBox(height: 12),
                          _PatienceMessage(locale: locale, accent: accent),
                          const SizedBox(height: 24),
                        ],

                        // Liste des étapes (visible dès qu'on lance)
                        if (sshState.steps.any((s) => s.status != StepStatus.pending)) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark ? ChillColorsDark.bgElevated : ChillColorsLight.bgElevated,
                              borderRadius: BorderRadius.circular(ChillRadius.xl),
                              border: Border.all(
                                color: isDark ? ChillColorsDark.border : ChillColorsLight.border,
                              ),
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

                        // Résultat final
                        if (sshState.isComplete) ...[
                          const SizedBox(height: 24),
                          _ResultCard(
                            locale: locale,
                            isDark: isDark,
                            accent: accent,
                            ipAddress: sshState.ipAddress,
                            username: sshState.username,
                          ),
                        ],

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

/// Carte explicative "Qu'est-ce que ça fait ?"
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
                t(locale, 'ssh.explanation.title'),
                style: theme.textTheme.titleMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t(locale, 'ssh.explanation.content'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// Loader animé avec espace pour le logo
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
                // Placeholder pour le logo/personnage
                // Remplacer par Image.asset('assets/images/logo.png') quand disponible
                child: Icon(Icons.terminal, color: accent, size: 36),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Message "Cela peut prendre plusieurs minutes" avec animation fade
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
          t(widget.locale, 'ssh.patience'),
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

/// Carte résultat avec IP et nom d'utilisateur
class _ResultCard extends StatelessWidget {
  final String locale;
  final bool isDark;
  final Color accent;
  final String? ipAddress;
  final String? username;

  const _ResultCard({
    required this.locale,
    required this.isDark,
    required this.accent,
    this.ipAddress,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectString = username != null && ipAddress != null ? '$username@$ipAddress' : '';

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

          // IP
          if (ipAddress != null) ...[
            Text(t(locale, 'ssh.result.ip'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            _CopyableInfo(value: ipAddress!, isDark: isDark),
            const SizedBox(height: 16),
          ],

          // Username
          if (username != null) ...[
            Text(t(locale, 'ssh.result.username'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            _CopyableInfo(value: username!, isDark: isDark),
            const SizedBox(height: 16),
          ],

          // Connexion string
          if (connectString.isNotEmpty) ...[
            Text(t(locale, 'ssh.result.connect'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            _CopyableInfo(value: connectString, isDark: isDark),
          ],
        ],
      ),
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
