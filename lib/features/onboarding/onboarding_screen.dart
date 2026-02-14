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

    final pages = _buildPages(locale, isDark);

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

  List<Widget> _buildPages(String locale, bool isDark) {
    final themeFolder = isDark ? 'dark' : 'light';

    return [
      // Page 1 : Bienvenue — mascotte à gauche
      _SplitPage(
        icon: Icons.hub,
        title: t(locale, 'onboarding.welcome.title'),
        description: t(locale, 'onboarding.welcome.desc'),
        leftWidget: Image.asset(
          'assets/images/mascot.png',
          fit: BoxFit.contain,
        ),
      ),
      // Page 2 : SSH — image à droite
      _SplitPage(
        icon: Icons.terminal,
        title: t(locale, 'onboarding.ssh.title'),
        description: t(locale, 'onboarding.ssh.desc'),
        rightWidget: _OnboardingImage(
          path: 'assets/images/onboarding/$locale/$themeFolder/1.png',
        ),
      ),
      // Page 3 : WoL — image à gauche
      _SplitPage(
        icon: Icons.power_settings_new,
        title: t(locale, 'onboarding.wol.title'),
        description: t(locale, 'onboarding.wol.desc'),
        leftWidget: _OnboardingImage(
          path: 'assets/images/onboarding/$locale/$themeFolder/2.png',
        ),
      ),
      // Page 4 : Tailscale — image à droite
      _SplitPage(
        icon: Icons.vpn_lock,
        title: t(locale, 'onboarding.tailscale.title'),
        description: t(locale, 'onboarding.tailscale.desc'),
        rightWidget: _OnboardingImage(
          path: 'assets/images/onboarding/$locale/$themeFolder/3.png',
        ),
      ),
      // Page 5 : Prêt — loader à droite
      _SplitPage(
        icon: Icons.rocket_launch,
        title: t(locale, 'onboarding.ready.title'),
        description: t(locale, 'onboarding.ready.desc'),
        rightWidget: Image.asset(
          'assets/images/loader.png',
          fit: BoxFit.contain,
        ),
      ),
    ];
  }
}

/// Page avec layout horizontal responsive : texte + image s'adaptent à la fenêtre
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Facteur d'échelle : 1.0 à 1200px, descend jusqu'à 0.5
        final scale = (w / 1200).clamp(0.5, 1.0);

        final textContent = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 380 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80 * scale,
                height: 80 * scale,
                decoration: BoxDecoration(
                  color: accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(ChillRadius.xxl),
                ),
                child: Icon(icon, size: 40 * scale, color: accent),
              ),
              SizedBox(height: 28 * scale),
              Text(
                title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16 * scale),
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
            padding: EdgeInsets.symmetric(horizontal: 32 * scale),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leftWidget != null) ...[
                  Flexible(
                    flex: 3,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: h * 0.6),
                      child: leftWidget!,
                    ),
                  ),
                  SizedBox(width: 32 * scale),
                ],
                Flexible(flex: 3, child: textContent),
                if (rightWidget != null) ...[
                  SizedBox(width: 32 * scale),
                  Flexible(
                    flex: 3,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: h * 0.6),
                      child: rightWidget!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Affiche une image d'onboarding (paysage 991×592) avec coins arrondis
class _OnboardingImage extends StatelessWidget {
  final String path;

  const _OnboardingImage({required this.path});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? ChillColorsDark.border : ChillColorsLight.border;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        child: Image.asset(
          path,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
