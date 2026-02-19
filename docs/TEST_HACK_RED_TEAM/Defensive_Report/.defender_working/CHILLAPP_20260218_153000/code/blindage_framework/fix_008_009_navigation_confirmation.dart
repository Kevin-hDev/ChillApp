// =============================================================
// FIX-008 : Route guards pour pages sensibles
// GAP-008: Navigation securisee absente (route guards)
// Cible: lib/config/router.dart
// =============================================================
// FIX-009 : Confirmation progressive commandes dangereuses
// GAP-009: Confirmation progressive absente pour commandes dangereuses
// Cible: lib/features/security/security_commands.dart (integration)
// =============================================================
//
// PROBLEME : Les pages contenant des infos sensibles (SSH, cles,
// settings) ne declenchent aucune protection. Les commandes
// destructrices (disable firewall, AppArmor) s'executent en un clic.
//
// SOLUTION :
// 1. Route guard qui marque les pages sensibles et active la
//    protection d'ecran quand on y navigue
// 2. Widget de confirmation 3 etapes avec delai pour les
//    commandes dangereuses (disable*)
// =============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

// =============================================
// PARTIE 1 : Route Guards (FIX-008)
// =============================================

/// Pages classees par niveau de sensibilite.
enum PageSensitivity {
  /// Pages publiques (dashboard)
  normal,

  /// Pages avec infos sensibles (SSH config, connexion info)
  sensitive,

  /// Pages critiques (settings, securite)
  critical,
}

/// Mapping route -> niveau de sensibilite.
const Map<String, PageSensitivity> routeSensitivity = {
  '/': PageSensitivity.normal,
  '/ssh': PageSensitivity.sensitive,
  '/wol': PageSensitivity.normal,
  '/info': PageSensitivity.sensitive,
  '/settings': PageSensitivity.critical,
  '/tailscale': PageSensitivity.sensitive,
  '/security': PageSensitivity.critical,
};

/// Callback invoque quand la sensibilite de la page change.
/// Permet d'activer/desactiver la protection d'ecran.
typedef SensitivityChangeCallback = void Function(
  PageSensitivity sensitivity,
  String route,
);

/// Observer de navigation qui detecte le niveau de sensibilite
/// et notifie l'app pour activer les protections.
class SecurityRouteObserver extends NavigatorObserver {
  final SensitivityChangeCallback onSensitivityChange;
  PageSensitivity _currentSensitivity = PageSensitivity.normal;

  SecurityRouteObserver({required this.onSensitivityChange});

  PageSensitivity get currentSensitivity => _currentSensitivity;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _evaluateRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _evaluateRoute(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _evaluateRoute(previousRoute);
  }

  void _evaluateRoute(Route<dynamic> route) {
    final routeName = route.settings.name ?? '/';
    final sensitivity =
        routeSensitivity[routeName] ?? PageSensitivity.normal;

    if (sensitivity != _currentSensitivity) {
      _currentSensitivity = sensitivity;
      onSensitivityChange(sensitivity, routeName);
    }
  }
}

// =============================================
// PARTIE 2 : Confirmation Progressive (FIX-009)
// =============================================

/// Resultat de la demande de confirmation.
enum ConfirmationResult {
  confirmed,
  cancelled,
  timedOut,
}

/// Niveau de danger d'une commande.
enum DangerLevel {
  /// Commandes reversibles (enable)
  low,

  /// Commandes a impact (disable firewall, etc.)
  medium,

  /// Commandes irreversibles (effacement, reset)
  high,
}

/// Widget qui force une confirmation progressive pour les
/// commandes dangereuses. 3 etapes :
/// 1. Avertissement avec detail de l'impact
/// 2. Delai obligatoire (3s pour medium, 5s pour high)
/// 3. Confirmation finale avec saisie du mot "CONFIRMER"
class ProgressiveConfirmation {
  /// Affiche la boite de dialogue de confirmation progressive.
  /// Retourne [ConfirmationResult.confirmed] seulement si
  /// l'utilisateur confirme toutes les etapes.
  static Future<ConfirmationResult> show({
    required BuildContext context,
    required String actionName,
    required String impactDescription,
    required DangerLevel dangerLevel,
  }) async {
    // Etape 1 : Avertissement
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              dangerLevel == DangerLevel.high
                  ? Icons.dangerous
                  : Icons.warning_amber_rounded,
              color: dangerLevel == DangerLevel.high
                  ? Colors.red
                  : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(actionName)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(impactDescription),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Cette action peut reduire la securite de votre systeme. '
                'Etes-vous sur de vouloir continuer ?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Je comprends le risque'),
          ),
        ],
      ),
    );

    if (step1 != true) return ConfirmationResult.cancelled;

    // Etape 2 : Delai obligatoire
    if (!context.mounted) return ConfirmationResult.cancelled;
    final delay = dangerLevel == DangerLevel.high
        ? const Duration(seconds: 5)
        : const Duration(seconds: 3);

    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CountdownDialog(delay: delay),
    );

    if (step2 != true) return ConfirmationResult.cancelled;

    // Etape 3 : Confirmation finale (seulement pour high)
    if (dangerLevel == DangerLevel.high) {
      if (!context.mounted) return ConfirmationResult.cancelled;
      final step3 = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _FinalConfirmationDialog(),
      );

      if (step3 != true) return ConfirmationResult.cancelled;
    }

    return ConfirmationResult.confirmed;
  }
}

/// Dialogue avec compte a rebours.
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
    return AlertDialog(
      title: const Text('Delai de securite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_remaining > 0)
            CircularProgressIndicator(
              value: 1 - (_remaining / widget.delay.inSeconds),
            ),
          const SizedBox(height: 16),
          Text(
            _remaining > 0
                ? 'Veuillez patienter $_remaining secondes...'
                : 'Vous pouvez maintenant confirmer.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _remaining == 0
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

/// Dialogue de confirmation finale (saisie "CONFIRMER").
class _FinalConfirmationDialog extends StatefulWidget {
  const _FinalConfirmationDialog();

  @override
  State<_FinalConfirmationDialog> createState() =>
      _FinalConfirmationDialogState();
}

class _FinalConfirmationDialogState extends State<_FinalConfirmationDialog> {
  final _controller = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final valid = _controller.text.trim().toUpperCase() == 'CONFIRMER';
      if (valid != _isValid) setState(() => _isValid = valid);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmation finale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tapez CONFIRMER pour valider cette action :'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'CONFIRMER',
              border: OutlineInputBorder(),
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
          onPressed: _isValid
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Executer'),
        ),
      ],
    );
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Dans lib/config/router.dart, ajouter l'observer :
//    final securityObserver = SecurityRouteObserver(
//      onSensitivityChange: (sensitivity, route) {
//        if (sensitivity == PageSensitivity.critical) {
//          // Activer la protection d'ecran (voir FIX-013)
//        }
//      },
//    );
//    // Ajouter dans GoRouter: observers: [securityObserver]
//
// 2. Dans security_commands.dart, envelopper les disable* :
//    Future<bool> safeDisableFirewall(BuildContext context) async {
//      final result = await ProgressiveConfirmation.show(
//        context: context,
//        actionName: 'Desactiver le pare-feu',
//        impactDescription: 'Le pare-feu protege votre PC...',
//        dangerLevel: DangerLevel.high,
//      );
//      if (result != ConfirmationResult.confirmed) return false;
//      return disableLinuxFirewall();
//    }
// =============================================================
