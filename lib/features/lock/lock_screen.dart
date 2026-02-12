import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/design_tokens.dart';
import '../../i18n/locale_provider.dart';
import 'lock_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Chiffres 0-9 (clavier principal et pavé numérique)
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _onDigit('0');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _onDigit('1');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      _onDigit('2');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      _onDigit('3');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      _onDigit('4');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      _onDigit('5');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      _onDigit('6');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      _onDigit('7');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      _onDigit('8');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      _onDigit('9');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _onDelete();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onDigit(String digit) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 8) {
      _verify();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    final locale = ref.read(localeProvider);
    final lockState = ref.read(lockProvider);

    if (lockState.failedAttempts >= 5) {
      setState(() {
        _error = t(locale, 'lock.tooMany');
        _pin = '';
      });
      _shakeController.forward(from: 0);
      return;
    }

    final ok = await ref.read(lockProvider.notifier).verifyPin(_pin);
    if (!ok) {
      setState(() {
        _error = t(locale, 'lock.error');
        _pin = '';
      });
      _shakeController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final locale = ref.watch(localeProvider);
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;
    final borderColor = isDark ? ChillColorsDark.border : ChillColorsLight.border;
    final surfaceColor = isDark ? ChillColorsDark.bgSurface : ChillColorsLight.bgSurface;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              // Logo
              Image.asset('assets/logo.png', width: 64, height: 64,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: accent,
                ),
              ),
              const SizedBox(height: 24),

              // Titre
              Text(
                t(locale, 'lock.title'),
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t(locale, 'lock.enter'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Cercles PIN
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  final dx = _shakeAnimation.value *
                      10 *
                      ((_shakeController.value * 4).remainder(2) > 1 ? -1 : 1);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? accent : Colors.transparent,
                        border: Border.all(
                          color: filled ? accent : borderColor,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // Erreur
              SizedBox(
                height: 20,
                child: _error != null
                    ? Text(
                        _error!,
                        style: TextStyle(
                          color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 24),

              // Pavé numérique
              SizedBox(
                width: 280,
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
                              return const SizedBox(width: 72, height: 72);
                            }
                            if (key == 'del') {
                              return SizedBox(
                                width: 72,
                                height: 72,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _onDelete,
                                    borderRadius: BorderRadius.circular(36),
                                    child: Center(
                                      child: Icon(
                                        Icons.backspace_outlined,
                                        color: isDark
                                            ? ChillColorsDark.textSecondary
                                            : ChillColorsLight.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return SizedBox(
                              width: 72,
                              height: 72,
                              child: Material(
                                color: surfaceColor,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _onDigit(key),
                                  child: Center(
                                    child: Text(
                                      key,
                                      style: theme.textTheme.headlineSmall,
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
              ),
              ],
            ),
          ),
        ),
        ),
      ),
    ),
    );
  }
}

/// Widget réutilisable pour la saisie PIN dans les dialogues
class PinInputDialog extends ConsumerStatefulWidget {
  final String title;
  final String? subtitle;
  final ValueChanged<String> onComplete;

  const PinInputDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.onComplete,
  });

  @override
  ConsumerState<PinInputDialog> createState() => PinInputDialogState();
}

class PinInputDialogState extends ConsumerState<PinInputDialog> {
  String _pin = '';
  String? _error;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  static final _digitKeys = {
    LogicalKeyboardKey.digit0: '0', LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.digit1: '1', LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.digit2: '2', LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.digit3: '3', LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.digit4: '4', LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.digit5: '5', LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.digit6: '6', LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.digit7: '7', LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.digit8: '8', LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.digit9: '9', LogicalKeyboardKey.numpad9: '9',
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    if (digit != null) {
      _onDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _onDelete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onDigit(String digit) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 8) {
      widget.onComplete(_pin);
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  void setError(String message) {
    setState(() {
      _error = message;
      _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? ChillColorsDark.accent : ChillColorsLight.accent;
    final borderColor = isDark ? ChillColorsDark.border : ChillColorsLight.border;
    final surfaceColor = isDark ? ChillColorsDark.bgSurface : ChillColorsLight.bgSurface;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Cercles
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(8, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? accent : Colors.transparent,
                    border: Border.all(
                      color: filled ? accent : borderColor,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),

            // Erreur
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: isDark ? ChillColorsDark.red : ChillColorsLight.red,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Pavé numérique compact
            SizedBox(
              width: 240,
              child: Column(
                children: [
                  for (final row in [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['', '0', 'del'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row.map((key) {
                          if (key.isEmpty) {
                            return const SizedBox(width: 60, height: 60);
                          }
                          if (key == 'del') {
                            return SizedBox(
                              width: 60,
                              height: 60,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _onDelete,
                                  borderRadius: BorderRadius.circular(30),
                                  child: Center(
                                    child: Icon(
                                      Icons.backspace_outlined,
                                      size: 20,
                                      color: isDark
                                          ? ChillColorsDark.textSecondary
                                          : ChillColorsLight.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return SizedBox(
                            width: 60,
                            height: 60,
                            child: Material(
                              color: surfaceColor,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _onDigit(key),
                                child: Center(
                                  child: Text(
                                    key,
                                    style: theme.textTheme.titleLarge,
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
            ),
          ],
        ),
      ),
    ),
    );
  }
}
