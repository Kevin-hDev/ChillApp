import 'package:flutter/material.dart';
import '../../../config/design_tokens.dart';
import '../../../shared/extensions/chill_theme.dart';

/// Un service système détecté sur la machine
class ServiceItem {
  final String name;
  final String displayName;
  final bool isActive;

  const ServiceItem({
    required this.name,
    required this.displayName,
    required this.isActive,
  });
}

/// Carte dépliable spéciale pour le toggle "Services inutiles" de Linux.
/// Affiche une liste de services détectés avec un bouton activer/désactiver chacun.
class ServicesToggleCard extends StatefulWidget {
  final String title;
  final String description;
  final List<ServiceItem> services;
  final bool isLoading;
  final Set<String> loadingServices;
  final ValueChanged<String>? onToggleService;

  const ServicesToggleCard({
    super.key,
    required this.title,
    required this.description,
    this.services = const [],
    this.isLoading = false,
    this.loadingServices = const {},
    this.onToggleService,
  });

  @override
  State<ServicesToggleCard> createState() => _ServicesToggleCardState();
}

class _ServicesToggleCardState extends State<ServicesToggleCard> {
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
                // Ligne principale
                Row(
                  children: [
                    Icon(
                      Icons.miscellaneous_services,
                      size: 22,
                      color: context.chillAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isLoading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.chillAccent,
                        ),
                      )
                    else
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: context.chillTextSecondary,
                      ),
                  ],
                ),
                // Contenu déplié
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.chillTextSecondary,
                      height: 1.5,
                    ),
                  ),
                  if (widget.services.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...widget.services.map((service) => _ServiceRow(
                          service: service,
                          isLoading: widget.loadingServices.contains(service.name),
                          onToggle: () => widget.onToggleService?.call(service.name),
                        )),
                  ],
                  if (widget.services.isEmpty && !widget.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Aucun service désactivable détecté.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.chillTextMuted,
                          fontStyle: FontStyle.italic,
                        ),
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
}

class _ServiceRow extends StatelessWidget {
  final ServiceItem service;
  final bool isLoading;
  final VoidCallback? onToggle;

  const _ServiceRow({
    required this.service,
    required this.isLoading,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 34),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  service.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.chillTextMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.chillAccent,
              ),
            )
          else
            Switch(
              value: service.isActive,
              onChanged: (_) => onToggle?.call(),
            ),
        ],
      ),
    );
  }
}
