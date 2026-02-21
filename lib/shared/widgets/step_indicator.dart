import 'package:flutter/material.dart';
import '../extensions/chill_theme.dart';
import '../models/setup_step.dart';

class StepIndicator extends StatelessWidget {
  final String label;
  final StepStatus status;

  const StepIndicator({super.key, required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildIcon(context),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    switch (status) {
      case StepStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          color: context.chillTextMuted,
          size: 24,
        );
      case StepStatus.running:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StepStatus.success:
        return Icon(Icons.check_circle, color: context.chillAccent, size: 24);
      case StepStatus.error:
        return Icon(Icons.error, color: context.chillRed, size: 24);
    }
  }
}
