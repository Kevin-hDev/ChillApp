import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import '../extensions/chill_theme.dart';

/// Carte explicative "Qu'est-ce que ca fait ?"
class ExplanationCard extends StatelessWidget {
  final String titleKey;
  final String contentKey;
  final String locale;

  const ExplanationCard({
    super.key,
    required this.titleKey,
    required this.contentKey,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.chillBgElevated,
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        border: Border.all(color: context.chillBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: context.chillAccent, size: 22),
              const SizedBox(width: 10),
              Text(
                t(locale, titleKey),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: context.chillAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t(locale, contentKey),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
