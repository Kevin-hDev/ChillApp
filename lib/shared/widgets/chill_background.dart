import 'dart:math';
import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';

/// Fond d'écran reproduisant les effets visuels du site web Chill :
/// dot grid, lueur verte, ondulations subtiles.
class ChillBackground extends StatefulWidget {
  final Widget child;
  final bool showDividerAfterHeader;

  const ChillBackground({
    super.key,
    required this.child,
    this.showDividerAfterHeader = false,
  });

  @override
  State<ChillBackground> createState() => _ChillBackgroundState();
}

class _ChillBackgroundState extends State<ChillBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _driftController;

  @override
  void initState() {
    super.initState();
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  @override
  void dispose() {
    _driftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Lueur verte en haut
        Positioned(
          top: -100,
          left: 0,
          right: 0,
          height: 500,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [
                    isDark
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF059669).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
        ),

        // Ondulations concentriques (ripple arcs)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 400,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RippleArcsPainter(isDark: isDark),
            ),
          ),
        ),

        // Grille de points avec dérive
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _driftController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _DotGridPainter(
                    isDark: isDark,
                    driftProgress: _driftController.value,
                  ),
                );
              },
            ),
          ),
        ),

        // Contenu
        widget.child,
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
    final borderColor =
        isDark ? ChillColorsDark.border : ChillColorsLight.border;

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

/// Peint la grille de points (dot grid) avec masque radial et animation de dérive
class _DotGridPainter extends CustomPainter {
  final bool isDark;
  final double driftProgress;

  _DotGridPainter({required this.isDark, required this.driftProgress});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    const dotRadius = 0.8;
    final dotColor = isDark
        ? const Color(0xFF3A3D45)
        : const Color(0xFF9CA3AF);

    // Décalage de dérive (animation lente)
    final driftOffset = driftProgress * spacing;

    final center = Offset(size.width / 2, size.height * 0.4);

    final paint = Paint()..style = PaintingStyle.fill;

    for (double x = -spacing + driftOffset;
        x < size.width + spacing;
        x += spacing) {
      for (double y = -spacing + driftOffset;
          y < size.height + spacing;
          y += spacing) {
        // Masque radial elliptique (comme le site : 70% x 60% au centre)
        final dx = (x - center.dx) / (size.width * 0.35);
        final dy = (y - center.dy) / (size.height * 0.3);
        final dist = sqrt(dx * dx + dy * dy);

        if (dist > 1.0) continue;

        // Opacité qui diminue vers les bords (comme mask-image)
        double opacity;
        if (dist < 0.3) {
          opacity = 0.55;
        } else {
          opacity = 0.55 * (1.0 - (dist - 0.3) / 0.7);
        }

        paint.color = dotColor.withValues(alpha: opacity.clamp(0.0, 0.55));
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.driftProgress != driftProgress ||
      oldDelegate.isDark != isDark;
}

/// Peint les ondulations concentriques subtiles en haut (ripple arcs)
class _RippleArcsPainter extends CustomPainter {
  final bool isDark;

  _RippleArcsPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (!isDark) return; // Les arcs sont très subtils, visibles surtout en dark

    final paint = Paint()
      ..color = const Color(0xFF1E8232).withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    const centerY = -120.0; // Au-dessus de la fenêtre, comme le site

    // Arcs concentriques espacés de 40px (comme le CSS : transparent 40px)
    for (double r = 40; r < 500; r += 40) {
      final rx = r * 2.0; // Ellipse plus large que haute
      final ry = r;

      // Masque : opacité qui diminue avec la distance
      final fade = (1.0 - (r / 500)).clamp(0.0, 1.0);
      paint.color = Color(0xFF1E8232).withValues(alpha: 0.07 * fade);

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
