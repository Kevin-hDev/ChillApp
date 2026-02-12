import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';
import '../extensions/chill_theme.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final bool isConfigured;

  const StatusBadge({
    super.key,
    required this.label,
    required this.isConfigured,
  });

  @override
  Widget build(BuildContext context) {
    final color = isConfigured ? context.chillAccent : context.chillTextMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ChillRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
