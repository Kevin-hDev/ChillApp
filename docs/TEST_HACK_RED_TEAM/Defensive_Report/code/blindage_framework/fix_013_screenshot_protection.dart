// =============================================================
// FIX-013 : Protection contre la capture d'ecran (desktop)
// GAP-013: Protection capture d'ecran absente (desktop)
// Cible: lib/core/security/screenshot_protection.dart
// =============================================================
//
// PROBLEME : Un malware peut capturer l'ecran et lire les cles
// SSH, tokens, mots de passe affiches dans l'app.
//
// SOLUTION :
// 1. Masquage des champs sensibles (par defaut)
// 2. Bouton "Reveler" avec auto-masquage apres 10s
// 3. Detection de processus de capture connus (Linux/macOS)
// 4. Notification a l'utilisateur si capture detectee
// =============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

/// Detecteur de processus de capture d'ecran.
class ScreenCaptureDetector {
  /// Processus connus de capture d'ecran.
  static const List<String> _captureProcesses = [
    // Linux
    'obs', 'obs-studio', 'simplescreenrecorder', 'kazam',
    'peek', 'vokoscreen', 'ffmpeg', 'recordmydesktop',
    'scrot', 'flameshot', 'spectacle', 'gnome-screenshot',
    // macOS
    'screencaptureui', 'QuickTime Player',
    // Windows
    'obs64', 'obs32', 'ShareX', 'Greenshot',
    'SnippingTool', 'ScreenClip',
    // Outils de hacking
    'xdotool', 'xwd', 'import', // ImageMagick
  ];

  /// Verifie si un processus de capture est actif.
  /// Retourne la liste des processus detectes.
  static Future<List<String>> detectCaptureProcesses() async {
    final detected = <String>[];

    try {
      if (Platform.isLinux) {
        // ps aux et filtrer
        final result = await Process.run('ps', ['aux']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().toLowerCase();
          for (final proc in _captureProcesses) {
            if (lines.contains(proc.toLowerCase())) {
              detected.add(proc);
            }
          }
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('ps', ['-A', '-o', 'comm=']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().toLowerCase();
          for (final proc in _captureProcesses) {
            if (lines.contains(proc.toLowerCase())) {
              detected.add(proc);
            }
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-Process | Select-Object -ExpandProperty ProcessName',
        ]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().toLowerCase();
          for (final proc in _captureProcesses) {
            if (lines.contains(proc.toLowerCase())) {
              detected.add(proc);
            }
          }
        }
      }
    } catch (_) {
      // Silencieux si la detection echoue
    }

    return detected;
  }

  /// Scan periodique en arriere-plan.
  static Timer startPeriodicScan({
    required void Function(List<String> processes) onDetected,
    Duration interval = const Duration(seconds: 30),
  }) {
    return Timer.periodic(interval, (_) async {
      final processes = await detectCaptureProcesses();
      if (processes.isNotEmpty) {
        onDetected(processes);
      }
    });
  }
}

/// Widget qui masque les donnees sensibles avec un bouton
/// pour les reveler temporairement.
class SensitiveDataField extends StatefulWidget {
  /// La donnee sensible a proteger.
  final String data;

  /// Label du champ.
  final String label;

  /// Duree avant auto-masquage (par defaut 10 secondes).
  final Duration revealDuration;

  /// Style du texte (optionnel).
  final TextStyle? textStyle;

  const SensitiveDataField({
    super.key,
    required this.data,
    required this.label,
    this.revealDuration = const Duration(seconds: 10),
    this.textStyle,
  });

  @override
  State<SensitiveDataField> createState() => _SensitiveDataFieldState();
}

class _SensitiveDataFieldState extends State<SensitiveDataField> {
  bool _revealed = false;
  Timer? _autoHideTimer;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() {
      _revealed = !_revealed;
    });

    _autoHideTimer?.cancel();
    if (_revealed) {
      // Auto-masquage apres la duree configuree
      _autoHideTimer = Timer(widget.revealDuration, () {
        if (mounted) {
          setState(() => _revealed = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: SelectableText(
                  _revealed ? widget.data : _mask(widget.data),
                  style: widget.textStyle ??
                      TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 13,
                        color: _revealed
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.3),
                      ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              tooltip: _revealed ? 'Masquer' : 'Reveler (${widget.revealDuration.inSeconds}s)',
              onPressed: _toggleReveal,
            ),
          ],
        ),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Auto-masquage dans ${widget.revealDuration.inSeconds}s',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  /// Masque une donnee en preservant la longueur.
  static String _mask(String data) {
    if (data.length <= 4) return '****';
    // Montrer les 2 premiers et 2 derniers caracteres
    return '${data.substring(0, 2)}${'*' * (data.length - 4)}${data.substring(data.length - 2)}';
  }
}

/// Banniere d'avertissement quand une capture d'ecran est detectee.
class ScreenCaptureWarning extends StatelessWidget {
  final List<String> detectedProcesses;
  final VoidCallback? onDismiss;

  const ScreenCaptureWarning({
    super.key,
    required this.detectedProcesses,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: Colors.red.withValues(alpha: 0.1),
      leading: const Icon(Icons.warning, color: Colors.red),
      content: Text(
        'Processus de capture detecte : ${detectedProcesses.join(", ")}. '
        'Les donnees sensibles sont masquees.',
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Compris'),
        ),
      ],
    );
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Creer lib/core/security/screenshot_protection.dart
//
// 2. Dans app.dart (initState du widget principal) :
//    late Timer _captureScanner;
//    @override
//    void initState() {
//      super.initState();
//      _captureScanner = ScreenCaptureDetector.startPeriodicScan(
//        onDetected: (processes) {
//          // Afficher ScreenCaptureWarning
//          // Forcer le masquage de tous les SensitiveDataField
//        },
//      );
//    }
//
// 3. Remplacer les Text() affichant des donnees sensibles par :
//    SensitiveDataField(
//      data: sshKey,
//      label: 'Cle SSH publique',
//    )
// =============================================================
