import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';
import '../extensions/chill_theme.dart';

/// Banniere d'erreur avec icone d'avertissement
class ErrorBanner extends StatelessWidget {
  final String message;

  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.chillRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ChillRadius.lg),
        border: Border.all(
          color: context.chillRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.chillRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.chillRed),
            ),
          ),
        ],
      ),
    );
  }
}
