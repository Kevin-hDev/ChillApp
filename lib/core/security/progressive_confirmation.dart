// =============================================================
// FIX-009 : Confirmation progressive pour commandes dangereuses
// GAP-009 : Confirmation progressive absente pour actions critiques
// Cible  : lib/core/security/progressive_confirmation.dart
// =============================================================
//
// PROBLEME : Les actions de securite critiques (desactiver le
// pare-feu, AppArmor, etc.) peuvent etre declenchees en un seul
// clic, sans aucune friction protective.
//
// SOLUTION : Dialogue en deux ou trois etapes selon le danger :
//   1. Avertissement avec description de l'impact
//   2. Delai obligatoire (3s medium, 5s high) avec compte a rebours
//   3. [high uniquement] Saisie du mot "CONFIRMER" pour finaliser
// =============================================================

import 'dart:async';
import 'package:flutter/material.dart';

// -----------------------------------------------------------
// Enumerations publiques
// -----------------------------------------------------------

/// Niveau de danger d'une action de securite.
enum DangerLevel {
  /// Action a impact notable (ex. desactiver le pare-feu).
  medium,

  /// Action a impact severe ou difficilement reversible
  /// (ex. supprimer AppArmor, effacer des cles).
  high,
}

/// Resultat retourne par [ProgressiveConfirmation.show].
enum ConfirmationResult {
  /// L'utilisateur a confirme toutes les etapes.
  confirmed,

  /// L'utilisateur a annule a l'une des etapes.
  cancelled,

  /// La session a expire (usage futur).
  timedOut,
}

// -----------------------------------------------------------
// Classe principale
// -----------------------------------------------------------

/// Affiche un dialogue de confirmation en plusieurs etapes pour
/// proteger les actions de securite dangereuses.
///
/// Usage :
/// ```dart
/// final result = await ProgressiveConfirmation.show(
///   context: context,
///   title: 'Desactiver le pare-feu',
///   description: 'Le pare-feu protege votre machine...',
///   level: DangerLevel.high,
/// );
/// if (result == ConfirmationResult.confirmed) {
///   // executer l'action
/// }
/// ```
class ProgressiveConfirmation {
  ProgressiveConfirmation._(); // Classe utilitaire — pas d'instance

  /// Affiche la sequence de confirmation et retourne le resultat.
  ///
  /// - [title]       : Nom court de l'action (ex. "Desactiver le pare-feu")
  /// - [description] : Explication claire de l'impact
  /// - [level]       : Niveau de danger ([DangerLevel.medium] ou [DangerLevel.high])
  static Future<ConfirmationResult> show({
    required BuildContext context,
    required String title,
    required String description,
    required DangerLevel level,
  }) async {
    // ----- Etape 1 : Dialogue d'avertissement -----
    final etape1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AvertissementDialog(
        title: title,
        description: description,
        level: level,
      ),
    );

    if (etape1 != true) return ConfirmationResult.cancelled;

    // ----- Etape 2 : Delai obligatoire avec compte a rebours -----
    if (!context.mounted) return ConfirmationResult.cancelled;

    final delai = level == DangerLevel.high
        ? const Duration(seconds: 5)
        : const Duration(seconds: 3);

    final etape2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CountdownDialog(delay: delai),
    );

    if (etape2 != true) return ConfirmationResult.cancelled;

    // ----- Etape 3 : Saisie "CONFIRMER" (uniquement pour high) -----
    if (level == DangerLevel.high) {
      if (!context.mounted) return ConfirmationResult.cancelled;

      final etape3 = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _FinalConfirmationDialog(),
      );

      if (etape3 != true) return ConfirmationResult.cancelled;
    }

    return ConfirmationResult.confirmed;
  }
}

// -----------------------------------------------------------
// Dialogue interne — Etape 1 : Avertissement
// -----------------------------------------------------------

class _AvertissementDialog extends StatelessWidget {
  final String title;
  final String description;
  final DangerLevel level;

  const _AvertissementDialog({
    required this.title,
    required this.description,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = level == DangerLevel.high;
    // .shade500 retourne un Color (et non un MaterialColor) qui supporte withValues
    final Color couleurDanger = isHigh ? Colors.red.shade500 : Colors.orange.shade500;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isHigh ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
            color: couleurDanger,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: couleurDanger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: couleurDanger.withValues(alpha: 0.4)),
            ),
            child: Text(
              isHigh
                  ? 'ATTENTION : Cette action est potentiellement irreversible '
                      'et peut gravement compromettre la securite de votre systeme.'
                  : 'Cette action peut reduire la protection de votre systeme. '
                      'Etes-vous sur de vouloir continuer ?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: couleurDanger,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: couleurDanger),
          child: Text(
            isHigh ? 'Je comprends le danger' : 'Je comprends le risque',
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------
// Dialogue interne — Etape 2 : Compte a rebours
// -----------------------------------------------------------

class _CountdownDialog extends StatefulWidget {
  final Duration delay;

  const _CountdownDialog({required this.delay});

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.delay.inSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progression = 1.0 - (_remaining / widget.delay.inSeconds);

    return AlertDialog(
      title: const Text('Delai de securite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _remaining > 0 ? progression : 1.0,
                  strokeWidth: 5,
                  color: _remaining > 0 ? Colors.orange : Colors.green,
                ),
                Text(
                  '$_remaining',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _remaining > 0 ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _remaining > 0
                ? 'Veuillez patienter $_remaining seconde${_remaining > 1 ? 's' : ''}...'
                : 'Vous pouvez maintenant confirmer.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          // Bouton desactive pendant le decompte
          onPressed: _remaining == 0
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------
// Dialogue interne — Etape 3 : Saisie de "CONFIRMER"
// -----------------------------------------------------------

class _FinalConfirmationDialog extends StatefulWidget {
  const _FinalConfirmationDialog();

  @override
  State<_FinalConfirmationDialog> createState() =>
      _FinalConfirmationDialogState();
}

class _FinalConfirmationDialogState extends State<_FinalConfirmationDialog> {
  final _controller = TextEditingController();
  bool _valide = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChange);
  }

  void _onTextChange() {
    final valide = _controller.text.trim().toUpperCase() == 'CONFIRMER';
    if (valide != _valide) setState(() => _valide = valide);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.lock_open_rounded, color: Colors.red, size: 22),
          SizedBox(width: 8),
          Text('Confirmation finale'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pour confirmer cette action dangereuse, tapez exactement :',
          ),
          const SizedBox(height: 8),
          const Text(
            'CONFIRMER',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 2,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'CONFIRMER',
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _valide ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              suffixIcon: _valide
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valide ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Executer'),
        ),
      ],
    );
  }
}
