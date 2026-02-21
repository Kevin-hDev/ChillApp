import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// =============================================================
// FIX-013 : Screenshot Protection
// =============================================================
//
// Trois composants :
//   1. ScreenCaptureDetector  — détecte les processus de capture
//                               via l'inspection de la liste des
//                               processus en cours (ps / Get-Process)
//   2. SensitiveDataField     — widget Flutter qui masque une donnée
//                               sensible avec bouton de révélation
//                               et minuterie d'auto-masquage
//   3. ScreenCaptureWarning   — bannière d'alerte MaterialBanner
// =============================================================

// ---------------------------------------------------------------------------
// 1. ScreenCaptureDetector
// ---------------------------------------------------------------------------

/// Détecte les logiciels de capture d'écran actifs sur le système.
///
/// La détection repose sur la liste des processus : elle ne peut pas
/// détecter les captures matérielles (touche Impr. écran) ni les
/// captures via l'API système bas niveau.
class ScreenCaptureDetector {
  /// Liste des noms de processus connus pour effectuer des captures.
  static const List<String> _captureProcesses = [
    // Linux
    'obs',
    'obs-studio',
    'simplescreenrecorder',
    'kazam',
    'peek',
    'vokoscreen',
    'ffmpeg',
    'recordmydesktop',
    'scrot',
    'flameshot',
    'spectacle',
    'gnome-screenshot',
    'xdotool',
    'xwd',
    'import', // ImageMagick import
    // macOS
    'screencaptureui',
    'QuickTime Player',
    'obs64',
    'obs32',
    // Windows
    'ShareX',
    'Greenshot',
    'SnippingTool',
    'ScreenClip',
  ];

  /// Retourne la liste des processus de capture actuellement détectés.
  /// Retourne une liste vide en cas d'erreur ou si aucun processus n'est trouvé.
  static Future<List<String>> detectCaptureProcesses() async {
    try {
      final runningProcesses = await _getRunningProcessNames();
      return _captureProcesses
          .where((p) => runningProcesses.any(
                (running) => running.toLowerCase().contains(p.toLowerCase()),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Lance une analyse périodique toutes les [intervalSeconds] secondes.
  /// Appelle [onDetected] avec la liste des processus détectés si non vide.
  /// Retourne un [Timer] qu'il faut annuler lors du dispose du widget.
  static Timer startPeriodicScan({
    required void Function(List<String> detectedProcesses) onDetected,
    int intervalSeconds = 10,
  }) {
    return Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      final detected = await detectCaptureProcesses();
      if (detected.isNotEmpty) {
        onDetected(detected);
      }
    });
  }

  /// Récupère la liste des noms de processus actifs selon l'OS.
  static Future<List<String>> _getRunningProcessNames() async {
    ProcessResult result;

    if (Platform.isWindows) {
      result = await Process.run(
        'powershell',
        ['-Command', 'Get-Process | Select-Object -ExpandProperty Name'],
      );
    } else {
      // Linux et macOS
      result = await Process.run(
        'ps',
        ['-eo', 'comm'],
        runInShell: false,
      );
    }

    if (result.exitCode != 0) return [];

    final output = result.stdout as String;
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Masque une donnée sensible : affiche les 2 premiers et 2 derniers
  /// caractères, le reste est remplacé par des étoiles.
  /// Si la chaîne fait 4 caractères ou moins, retourne '****'.
  static String maskData(String data) {
    if (data.length <= 4) return '****';
    return '${data.substring(0, 2)}${'*' * (data.length - 4)}${data.substring(data.length - 2)}';
  }
}

// ---------------------------------------------------------------------------
// 2. SensitiveDataField
// ---------------------------------------------------------------------------

/// Widget Flutter affichant une donnée sensible masquée par défaut.
///
/// Un bouton "Révéler" permet d'afficher la valeur en clair pendant
/// [autoHideDuration] secondes avant de la remasquer automatiquement.
class SensitiveDataField extends StatefulWidget {
  /// La donnée sensible à afficher (en clair en interne, masquée par défaut).
  final String data;

  /// Durée d'affichage en clair avant remasquage automatique.
  final Duration autoHideDuration;

  /// Style optionnel pour le texte affiché.
  final TextStyle? textStyle;

  /// Label descriptif affiché au-dessus de la donnée.
  final String? label;

  const SensitiveDataField({
    super.key,
    required this.data,
    this.autoHideDuration = const Duration(seconds: 10),
    this.textStyle,
    this.label,
  });

  @override
  State<SensitiveDataField> createState() => _SensitiveDataFieldState();
}

class _SensitiveDataFieldState extends State<SensitiveDataField> {
  bool _revealed = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    if (_revealed) {
      _hide();
    } else {
      _reveal();
    }
  }

  void _reveal() {
    _hideTimer?.cancel();
    setState(() => _revealed = true);
    _hideTimer = Timer(widget.autoHideDuration, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _revealed
        ? widget.data
        : ScreenCaptureDetector.maskData(widget.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                displayText,
                style: widget.textStyle ??
                    const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 14,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: _revealed ? 'Masquer' : 'Révéler',
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              onPressed: _toggleReveal,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. ScreenCaptureWarning
// ---------------------------------------------------------------------------

/// Bannière d'alerte affichée lorsqu'un logiciel de capture est détecté.
///
/// S'intègre dans le [Scaffold] via [ScaffoldMessenger.of(context).showMaterialBanner].
class ScreenCaptureWarning extends StatelessWidget {
  /// Liste des noms des processus de capture détectés.
  final List<String> detectedProcesses;

  /// Callback appelé lorsque l'utilisateur ferme la bannière.
  final VoidCallback onDismiss;

  const ScreenCaptureWarning({
    super.key,
    required this.detectedProcesses,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final processNames = detectedProcesses.join(', ');

    return MaterialBanner(
      backgroundColor: Colors.orange.shade900,
      leading: const Icon(
        Icons.warning_amber_rounded,
        color: Colors.white,
        size: 28,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Logiciel de capture détecté',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Processus : $processNames',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Des données sensibles visibles à l\'écran peuvent être enregistrées.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text(
            'Fermer',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
