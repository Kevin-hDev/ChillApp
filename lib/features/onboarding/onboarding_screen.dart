import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../../shared/widgets/chill_background.dart';
import 'onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    final pages = _buildPages(locale);

    return Scaffold(
      body: ChillBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, i) => pages[i],
                ),
              ),
              // Indicateurs de page
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentPage
                            ? accent
                            : accent.withAlpha(60),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              // Bouton Continuer / Commencer
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage < pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        ref.read(onboardingProvider.notifier).complete();
                      }
                    },
                    child: Text(
                      _currentPage < pages.length - 1
                          ? t(locale, 'onboarding.continue')
                          : t(locale, 'onboarding.start'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPages(String locale) {
    return [
      // Page 1 : Bienvenue — mascotte à gauche uniquement
      _SplitPage(
        icon: Icons.hub,
        title: t(locale, 'onboarding.welcome.title'),
        description: t(locale, 'onboarding.welcome.desc'),
        leftWidget: Image.asset(
          'assets/images/mascot.png',
          height: 270,
          fit: BoxFit.contain,
        ),
      ),
      // Page 2 : SSH — screenshot à droite
      _SplitPage(
        icon: Icons.terminal,
        title: t(locale, 'onboarding.ssh.title'),
        description: t(locale, 'onboarding.ssh.desc'),
        rightWidget: _ScreenshotPlaceholder(
          imagePath: 'assets/images/screenshot.png',
        ),
      ),
      // Page 3 : WoL — screenshot à gauche
      _SplitPage(
        icon: Icons.power_settings_new,
        title: t(locale, 'onboarding.wol.title'),
        description: t(locale, 'onboarding.wol.desc'),
        leftWidget: _ScreenshotPlaceholder(
          imagePath: 'assets/images/screenshot.png',
        ),
      ),
      // Page 4 : Tailscale — screenshot à droite
      _SplitPage(
        icon: Icons.vpn_lock,
        title: t(locale, 'onboarding.tailscale.title'),
        description: t(locale, 'onboarding.tailscale.desc'),
        rightWidget: _ScreenshotPlaceholder(
          imagePath: 'assets/images/screenshot.png',
        ),
      ),
      // Page 5 : Prêt — mascotte à droite
      _SplitPage(
        icon: Icons.rocket_launch,
        title: t(locale, 'onboarding.ready.title'),
        description: t(locale, 'onboarding.ready.desc'),
        rightWidget: Image.asset(
          'assets/images/mascot.png',
          height: 270,
          fit: BoxFit.contain,
        ),
      ),
    ];
  }
}

/// Page avec layout horizontal : icône/texte au centre, images à gauche/droite
/// Le groupe (texte + image) est centré sur la page
class _SplitPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? leftWidget;
  final Widget? rightWidget;

  const _SplitPage({
    required this.icon,
    required this.title,
    required this.description,
    this.leftWidget,
    this.rightWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    final textContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: accent.withAlpha(25),
              borderRadius: BorderRadius.circular(ChillRadius.xxl),
            ),
            child: Icon(icon, size: 40, color: accent),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? ChillColorsDark.textSecondary
                  : ChillColorsLight.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leftWidget != null) ...[
              leftWidget!,
              const SizedBox(width: 48),
            ],
            textContent,
            if (rightWidget != null) ...[
              const SizedBox(width: 48),
              rightWidget!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Affiche un screenshot si le fichier existe, sinon un placeholder grisé
class _ScreenshotPlaceholder extends StatelessWidget {
  final String imagePath;

  const _ScreenshotPlaceholder({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? ChillColorsDark.border : ChillColorsLight.border;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ChillRadius.xl),
      child: Image.asset(
        imagePath,
        height: 386,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Placeholder quand l'image n'existe pas encore
          return Container(
            height: 386,
            width: 180,
            decoration: BoxDecoration(
              color: borderColor.withAlpha(40),
              borderRadius: BorderRadius.circular(ChillRadius.xl),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 40,
                  color: isDark
                      ? ChillColorsDark.textMuted
                      : ChillColorsLight.textMuted,
                ),
                const SizedBox(height: 8),
                Text(
                  'Screenshot',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? ChillColorsDark.textMuted
                        : ChillColorsLight.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
