import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';
import '../../features/ssh_setup/ssh_setup_provider.dart';

class StepIndicator extends StatelessWidget {
  final String label;
  final StepStatus status;

  const StepIndicator({
    super.key,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildIcon(isDark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(bool isDark) {
    switch (status) {
      case StepStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          color: isDark ? ChillColorsDark.textMuted : ChillColorsLight.textMuted,
          size: 24,
        );
      case StepStatus.running:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StepStatus.success:
        return Icon(
          Icons.check_circle,
          color: isDark ? ChillColorsDark.accent : ChillColorsLight.accent,
          size: 24,
        );
      case StepStatus.error:
        return Icon(
          Icons.error,
          color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
          size: 24,
        );
    }
  }
}
