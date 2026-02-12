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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: accentColor, size: 32),
                  ?badge,
                ],
              ),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.titleLarge),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
