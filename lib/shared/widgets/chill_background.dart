import 'dart:math';
import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';

/// Fond d'écran reproduisant les effets visuels du site web Chill :
/// dot grid, lueur verte, ondulations subtiles.
class ChillBackground extends StatelessWidget {
  final Widget child;

  const ChillBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Lueur verte en haut — couvre toute la fenêtre, positionnée en haut
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  // Centré en haut au milieu (comme le CSS: top: -20%, left: 50%)
                  center: const Alignment(0.0, -1.2),
                  radius: 1.0,
                  colors: [
                    isDark
                        ? const Color(0xFF10B981).withValues(alpha: 0.10)
                        : const Color(0xFF059669).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
        ),

        // Ondulations concentriques (ripple arcs)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _RippleArcsPainter(isDark: isDark)),
          ),
        ),

        // Grille de points — statique, pas d'animation pour éviter le clignotement
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _DotGridPainter(isDark: isDark)),
          ),
        ),

        // Contenu
        child,
      ],
    );
  }
}

/// Ligne séparatrice fine avec dégradé (comme section-divider du site)
class ChillDivider extends StatelessWidget {
  const ChillDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? ChillColorsDark.border
        : ChillColorsLight.border;

    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            borderColor,
            borderColor,
            Colors.transparent,
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
    );
  }
}

/// Peint la grille de points (dot grid) avec masque radial
/// Centré en haut comme sur le site (ellipse 70% 60% at 50% 40%)
class _DotGridPainter extends CustomPainter {
  final bool isDark;

  _DotGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    const dotRadius = 0.8;
    final dotColor = isDark ? const Color(0xFF3A3D45) : const Color(0xFF9CA3AF);

    // Centre du masque elliptique : 50% horizontal, 40% vertical (comme le CSS)
    final centerX = size.width * 0.5;
    final centerY = size.height * 0.35;

    // Rayons de l'ellipse du masque (comme le CSS : 70% x 60%)
    final maskRx = size.width * 0.45;
    final maskRy = size.height * 0.45;

    final paint = Paint()..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        // Distance normalisée dans l'ellipse du masque
        final dx = (x - centerX) / maskRx;
        final dy = (y - centerY) / maskRy;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist > 1.0) continue;

        // Opacité : pleine au centre (< 30%), puis dégradé jusqu'au bord
        double opacity;
        if (dist < 0.3) {
          opacity = 0.55;
        } else {
          opacity = 0.55 * (1.0 - (dist - 0.3) / 0.7);
        }

        paint.color = dotColor.withValues(alpha: opacity);
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Peint les ondulations concentriques subtiles en haut (ripple arcs)
class _RippleArcsPainter extends CustomPainter {
  final bool isDark;

  _RippleArcsPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (!isDark) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    const centerY = -120.0;

    // Arcs concentriques (comme le CSS : ellipse 900x450 at 50% -120px, gap 40px)
    for (double r = 40; r < 500; r += 40) {
      final rx = r * 2.0;
      final ry = r;

      // Masque : opacité qui diminue avec la distance
      final fade = (1.0 - (r / 500)).clamp(0.0, 1.0);
      paint.color = const Color(0xFF1E8232).withValues(alpha: 0.07 * fade);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: rx,
          height: ry,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RippleArcsPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
