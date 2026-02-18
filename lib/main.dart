import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/security/secure_error_handler.dart';
import 'core/security/startup_security.dart';
import 'features/settings/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Vérifications de sécurité au démarrage (injection, debugger, Frida).
  // En mode release, exit(1) est appelé automatiquement si menace critique.
  await StartupSecurityChecker.runAllChecks();

  final prefs = await SharedPreferences.getInstance();

  // runSecureApp encapsule runApp dans une zone protégée (runZonedGuarded)
  // et configure FlutterError.onError pour éviter toute fuite d'information.
  SecureErrorHandler.runSecureApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const ChillApp(),
    ),
  );
}
