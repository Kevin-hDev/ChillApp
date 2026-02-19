// =============================================================
// FIX-002 : Error handling securise avec runZonedGuarded
// GAP-002 : Pas de runZonedGuarded pour error handling securise
// Cible : lib/main.dart
// =============================================================
//
// PROBLEME : runApp() est appele directement sans zone de capture.
// Les erreurs non gerees peuvent fuiter des stack traces avec
// des chemins internes, noms de fonctions et info sensibles.
//
// SOLUTION : Envelopper dans runZonedGuarded + FlutterError.onError.
// Filtrer les stack traces. Logger sans info sensible.
// =============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Gestionnaire d'erreurs securise pour l'application.
/// Ne fuite JAMAIS de stack traces, chemins ou secrets en production.
class SecureErrorHandler {
  /// Initialise la gestion d'erreurs securisee.
  /// Appeler AVANT runApp dans main().
  static void initialize() {
    // Capturer les erreurs Flutter (widgets, rendu, etc.)
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // En debug : afficher normalement
        FlutterError.presentError(details);
      } else {
        // En production : log sanitise uniquement
        _logSecure('FlutterError: ${details.exception.runtimeType}');
      }
    };

    // Capturer les erreurs de la couche PlatformDispatcher
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('PlatformError: $error\n$stack');
      } else {
        _logSecure('PlatformError: ${error.runtimeType}');
      }
      return true; // Marquer comme geree
    };
  }

  /// Execute l'application dans une zone securisee.
  /// Capture TOUTES les erreurs asynchrones non gerees.
  static void runSecureApp(Widget app) {
    runZonedGuarded(
      () {
        runApp(app);
      },
      (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('ZonedError: $error\n$stackTrace');
        } else {
          _logSecure('ZonedError: ${error.runtimeType}');
        }
      },
    );
  }

  /// Log securise : ne contient JAMAIS de chemins, IP, tokens ou secrets.
  static void _logSecure(String message) {
    // En production, on pourrait envoyer vers un service de monitoring
    // Pour l'instant, log minimal sans info sensible
    debugPrint('[SEC] $message');
  }

  /// Sanitise un message d'erreur avant affichage a l'utilisateur.
  /// Supprime les chemins, IPs, tokens et autres infos sensibles.
  static String sanitizeForUser(String errorMessage) {
    var sanitized = errorMessage;
    // Supprimer les chemins de fichiers
    sanitized = sanitized.replaceAll(RegExp(r'/[^\s:]+'), '[chemin]');
    sanitized = sanitized.replaceAll(RegExp(r'[A-Z]:\\[^\s:]+'), '[chemin]');
    // Supprimer les adresses IP
    sanitized = sanitized.replaceAll(
      RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?'),
      '[adresse]',
    );
    // Supprimer les tokens/cles potentiels (chaines longues base64/hex)
    sanitized = sanitized.replaceAll(
      RegExp(r'[A-Za-z0-9+/=]{24,}'),
      '[masque]',
    );
    return sanitized;
  }
}

// =============================================================
// INTEGRATION : Remplacer le main.dart existant par :
// =============================================================
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   SecureErrorHandler.initialize();
//   final prefs = await SharedPreferences.getInstance();
//   SecureErrorHandler.runSecureApp(
//     ProviderScope(
//       overrides: [
//         sharedPrefsProvider.overrideWithValue(prefs),
//       ],
//       child: const ChillApp(),
//     ),
//   );
// }
