import 'package:go_router/go_router.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/ssh_setup/ssh_setup_screen.dart';
import '../features/wol_setup/wol_setup_screen.dart';
import '../features/connection_info/connection_info_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tailscale/tailscale_screen.dart';

final router = GoRouter(
  initialLocation: '/',
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
  ],
);
