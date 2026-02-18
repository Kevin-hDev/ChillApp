import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/ssh_setup/ssh_setup_screen.dart';
import '../features/wol_setup/wol_setup_screen.dart';
import '../features/connection_info/connection_info_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/security/security_screen.dart';
import '../features/tailscale/tailscale_screen.dart';
import '../core/security/security_route_observer.dart';

/// SECURITE : La protection PIN est geree dans app.dart via un swap
/// MaterialApp / MaterialApp.router. Quand le PIN est actif et non deverrouille,
/// app.dart affiche LockScreen au lieu du router, ce qui bloque l'acces a TOUTES
/// les routes ci-dessous. Flutter desktop n'a pas de deep-linking, donc cette
/// approche est suffisante. TOUTE nouvelle route ajoutee ici est automatiquement
/// protegee par le lock dans app.dart.
final router = GoRouter(
  initialLocation: '/',
  observers: [securityRouteObserver],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Page non trouvée',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home),
            label: const Text('Retour à l\'accueil'),
          ),
        ],
      ),
    ),
  ),
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/ssh',
      builder: (context, state) => const SshSetupScreen(),
    ),
    GoRoute(
      path: '/wol',
      builder: (context, state) => const WolSetupScreen(),
    ),
    GoRoute(
      path: '/info',
      builder: (context, state) => const ConnectionInfoScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/tailscale',
      builder: (context, state) => const TailscaleScreen(),
    ),
    GoRoute(
      path: '/security',
      builder: (context, state) => const SecurityScreen(),
    ),
  ],
);

/// Instance de l'observer de sécurité des routes.
///
/// À enregistrer dans les `navigatorObservers` de MaterialApp :
/// ```dart
/// MaterialApp(
///   navigatorObservers: [securityRouteObserver],
///   ...
/// )
/// ```
final securityRouteObserver = SecurityRouteObserver(
  onSensitivityChange: (sensitivity, route) {
    // Journalisation — sera connecté à la protection screenshot ultérieurement
    debugPrint('[Security] Route $route → sensibilité : ${sensitivity.name}');
  },
);
