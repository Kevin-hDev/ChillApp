import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';

class ChillCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final Widget? badge;

  const ChillCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = constraints.maxHeight;
            final scale = (cardHeight / 160).clamp(0.6, 1.5);
            final padding = (16 * scale).clamp(10.0, 24.0);
            final iconSize = (28 * scale).clamp(18.0, 40.0);
            final titleSize = (18 * scale).clamp(12.0, 24.0);
            final descSize = (13 * scale).clamp(10.0, 16.0);
            final spacing = (8 * scale).clamp(4.0, 12.0);
            // Masquer la description si la carte est trop petite
            final showDesc = cardHeight > 100 && description.isNotEmpty;

            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(icon, color: accentColor, size: iconSize),
                      if (badge != null) Flexible(child: badge!),
                    ],
                  ),
                  SizedBox(height: spacing),
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: titleSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showDesc) ...[
                    SizedBox(height: spacing * 0.5),
                    Flexible(
                      child: Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: descSize),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
