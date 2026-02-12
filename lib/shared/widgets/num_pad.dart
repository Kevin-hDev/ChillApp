import 'package:flutter/material.dart';
import '../extensions/chill_theme.dart';

/// Pave numerique reutilisable
class NumPad extends StatelessWidget {
  final double buttonSize;
  final double width;
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const NumPad({
    super.key,
    this.buttonSize = 72,
    this.width = 280,
    required this.onDigit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', 'del'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((key) {
                  if (key.isEmpty) {
                    return SizedBox(width: buttonSize, height: buttonSize);
                  }
                  if (key == 'del') {
                    return Semantics(
                      button: true,
                      label: 'Supprimer',
                      child: SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onDelete,
                            borderRadius: BorderRadius.circular(buttonSize / 2),
                            child: Center(
                              child: Icon(
                                Icons.backspace_outlined,
                                color: context.chillTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Semantics(
                    button: true,
                    label: key,
                    child: SizedBox(
                      width: buttonSize,
                      height: buttonSize,
                      child: Material(
                        color: context.chillBgSurface,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onDigit(key),
                          child: Center(
                            child: Text(
                              key,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
