import 'package:flutter/material.dart';

// =============================================================
// FIX-008 : SecurityRouteObserver — Classification de sensibilité
//           des routes de navigation
// =============================================================
//
// Objectif : détecter en temps réel sur quelle page se trouve
// l'utilisateur et déclencher un callback selon le niveau de
// sensibilité (normal, sensitive, critical).
//
// Usage prévu : connecter ce callback à la protection
// contre les captures d'écran (screenshot protection).
// =============================================================

/// Niveau de sensibilité d'une page.
enum PageSensitivity {
  /// Page standard, aucune protection additionnelle requise.
  normal,

  /// Page contenant des données potentiellement sensibles.
  sensitive,

  /// Page contenant des données hautement confidentielles
  /// (clés, mots de passe, configuration de sécurité).
  critical,
}

/// Table de correspondance route → niveau de sensibilité.
/// Toute route non listée est traitée comme [PageSensitivity.normal].
const Map<String, PageSensitivity> routeSensitivity = {
  '/': PageSensitivity.normal,
  '/ssh': PageSensitivity.sensitive,
  '/wol': PageSensitivity.normal,
  '/info': PageSensitivity.sensitive,
  '/settings': PageSensitivity.critical,
  '/tailscale': PageSensitivity.sensitive,
  '/security': PageSensitivity.critical,
};

/// Callback déclenché lors d'un changement de sensibilité.
typedef SensitivityChangeCallback = void Function(
  PageSensitivity sensitivity,
  String route,
);

/// Observer de navigation qui évalue la sensibilité de chaque route
/// et notifie via [onSensitivityChange] lors d'un changement.
///
/// À enregistrer dans les `navigatorObservers` de MaterialApp.
class SecurityRouteObserver extends NavigatorObserver {
  final SensitivityChangeCallback onSensitivityChange;
  PageSensitivity _currentSensitivity = PageSensitivity.normal;

  SecurityRouteObserver({required this.onSensitivityChange});

  /// Sensibilité de la page actuellement affichée.
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
