import 'package:flutter/material.dart';
import '../../../config/design_tokens.dart';
import '../../../shared/extensions/chill_theme.dart';

/// Carte dépliable pour un toggle de sécurité.
/// Fermée : icône + titre + Switch (ou bouton Installer / loader)
/// Ouverte : ajoute le texte d'explication en dessous
class SecurityToggleCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool? isEnabled;
  final bool isLoading;
  final bool needsInstall;
  final String? installLabel;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onInstall;

  const SecurityToggleCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.isEnabled,
    this.isLoading = false,
    this.needsInstall = false,
    this.installLabel,
    this.onToggle,
    this.onInstall,
  });

  @override
  State<SecurityToggleCard> createState() => _SecurityToggleCardState();
}

class _SecurityToggleCardState extends State<SecurityToggleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne principale : icône + titre + action
                Row(
                  children: [
                    Icon(widget.icon, size: 22, color: context.chillAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildAction(context),
                  ],
                ),
                // Description dépliable
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.chillTextSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    // Loading
    if (widget.isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.chillAccent,
        ),
      );
    }

    // Needs install
    if (widget.needsInstall) {
      return TextButton(
        onPressed: widget.onInstall,
        child: Text(widget.installLabel ?? 'Installer'),
      );
    }

    // Normal toggle
    if (widget.isEnabled == null) {
      // State unknown / checking
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.chillTextMuted,
        ),
      );
    }

    // Status only (pas de toggle possible) — afficher un checkmark
    if (widget.onToggle == null) {
      return Icon(
        widget.isEnabled! ? Icons.check_circle : Icons.remove_circle_outline,
        color: widget.isEnabled! ? context.chillGreen : context.chillTextMuted,
        size: 24,
      );
    }

    return Switch(value: widget.isEnabled!, onChanged: widget.onToggle);
  }
}
