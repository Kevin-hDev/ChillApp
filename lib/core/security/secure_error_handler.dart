// =============================================================
// FIX-002 : Gestionnaire d'erreurs sécurisé
// GAP-002 : Pas de runZonedGuarded pour error handling sécurisé
// Fichier : lib/core/security/secure_error_handler.dart
// =============================================================
//
// PROBLÈME : runApp() était appelé directement sans zone de capture.
// Les erreurs non gérées pouvaient fuiter des stack traces contenant
// des chemins internes, noms de fonctions et informations sensibles.
//
// SOLUTION : Encapsuler dans runZonedGuarded + FlutterError.onError.
// Filtrer les messages avant affichage. Logger sans info sensible.
// =============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Gestionnaire d'erreurs sécurisé pour l'application.
/// Ne fuite JAMAIS de stack traces, chemins ou secrets en production.
class SecureErrorHandler {
  // Empêche l'instanciation — toutes les méthodes sont statiques.
  SecureErrorHandler._();

  /// Initialise la gestion d'erreurs sécurisée.
  /// Doit être appelé AVANT runApp dans main().
  static void _initialize() {
    // Capturer les erreurs Flutter (widgets, rendu, layout, etc.)
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // En debug : affichage complet pour faciliter le développement
        FlutterError.presentError(details);
      } else {
        // En production : log minimal sans information sensible
        _logSecure('FlutterError: ${details.exception.runtimeType}');
      }
    };

    // Capturer les erreurs de la couche PlatformDispatcher (Dart natif)
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('PlatformError: $error\n$stack');
      } else {
        _logSecure('PlatformError: ${error.runtimeType}');
      }
      return true; // Marquer l'erreur comme gérée
    };
  }

  /// Exécute l'application dans une zone sécurisée.
  /// Capture TOUTES les erreurs asynchrones non gérées.
  /// Remplace l'appel direct à runApp().
  static void runSecureApp(Widget app) {
    _initialize();
    runZonedGuarded(
      () {
        runApp(app);
      },
      (error, stackTrace) {
        if (kDebugMode) {
          // En debug : trace complète pour le développeur
          debugPrint('ZonedError: $error\n$stackTrace');
        } else {
          // En production : uniquement le type de l'erreur
          _logSecure('ZonedError: ${error.runtimeType}');
        }
      },
    );
  }

  /// Log sécurisé : ne contient JAMAIS de chemins, IP, tokens ou secrets.
  /// En production, ce log pourrait être envoyé vers un service de monitoring
  /// anonymisé (ex. Sentry avec données personnelles désactivées).
  static void _logSecure(String message) {
    debugPrint('[SEC] $message');
  }

  /// Sanitise un message d'erreur avant affichage à l'utilisateur.
  ///
  /// Supprime :
  /// - Les chemins de fichiers Unix (/home/user/..., /etc/..., etc.)
  /// - Les chemins de fichiers Windows (C:\Users\...)
  /// - Les adresses IP (avec port optionnel)
  /// - Les tokens/clés longs (chaînes alphanum > 24 caractères)
  ///
  /// En mode debug, le message original est retourné tel quel.
  /// En mode release, le message est systématiquement nettoyé.
  static String sanitizeForUser(String message) {
    if (kDebugMode) {
      return message;
    }
    return _sanitize(message);
  }

  /// Logique interne de sanitisation, appelable indépendamment du mode.
  /// Exposée comme méthode interne pour les tests unitaires.
  static String sanitize(String message) => _sanitize(message);

  static String _sanitize(String raw) {
    var result = raw;

    // 1. Supprimer les chemins Unix : /home/..., /etc/..., /usr/..., etc.
    //    Le pattern capture un slash suivi de caractères non-espaces/non-deux-points
    result = result.replaceAll(RegExp(r'/[^\s:]+'), '[chemin]');

    // 2. Supprimer les chemins Windows : C:\Users\..., D:\..., etc.
    result = result.replaceAll(RegExp(r'[A-Za-z]:\\[^\s:]+'), '[chemin]');

    // 3. Supprimer les adresses IP (avec ou sans port)
    result = result.replaceAll(
      RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?'),
      '[adresse]',
    );

    // 4. Supprimer les tokens/clés potentiels (chaînes base64/hex de plus de 24 chars)
    //    Cela couvre les JWT, API keys, secrets SSH, hashes, etc.
    result = result.replaceAll(
      RegExp(r'[A-Za-z0-9+/=_\-]{25,}'),
      '[masque]',
    );

    return result;
  }
}
