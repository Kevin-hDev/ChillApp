import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/security_route_observer.dart';

// =============================================================
// Tests : SecurityRouteObserver (FIX-008)
// =============================================================

/// Crée une route factice avec le nom donné.
Route<dynamic> _fakeRoute(String name) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox.shrink(),
  );
}

void main() {
  group('SecurityRouteObserver', () {
    late SecurityRouteObserver observer;
    late List<(PageSensitivity, String)> captured;

    setUp(() {
      captured = [];
      observer = SecurityRouteObserver(
        onSensitivityChange: (sensitivity, route) {
          captured.add((sensitivity, route));
        },
      );
    });

    // Test 1 : sensibilité initiale = normal
    test('sensibilité initiale est normal', () {
      expect(observer.currentSensitivity, equals(PageSensitivity.normal));
    });

    // Test 2 : didPush vers /settings → callback avec critical
    test('didPush vers /settings déclenche le callback avec critical', () {
      observer.didPush(_fakeRoute('/settings'), _fakeRoute('/'));
      expect(captured.length, equals(1));
      expect(captured.first.$1, equals(PageSensitivity.critical));
      expect(captured.first.$2, equals('/settings'));
      expect(observer.currentSensitivity, equals(PageSensitivity.critical));
    });

    // Test 3 : didPush vers / → callback avec normal
    // (d'abord pousser une route sensible pour permettre un changement)
    test('didPush vers / déclenche le callback avec normal après une route critique', () {
      observer.didPush(_fakeRoute('/security'), _fakeRoute('/'));
      captured.clear();
      observer.didPush(_fakeRoute('/'), _fakeRoute('/security'));
      expect(captured.length, equals(1));
      expect(captured.first.$1, equals(PageSensitivity.normal));
      expect(captured.first.$2, equals('/'));
    });

    // Test 4 : didPop vers la route précédente met à jour la sensibilité
    test('didPop met à jour la sensibilité selon la route précédente', () {
      // Naviguer vers /settings (critical)
      observer.didPush(_fakeRoute('/settings'), _fakeRoute('/ssh'));
      captured.clear();
      // Pop de /settings → retour à /ssh (sensitive)
      observer.didPop(_fakeRoute('/settings'), _fakeRoute('/ssh'));
      expect(captured.length, equals(1));
      expect(captured.first.$1, equals(PageSensitivity.sensitive));
      expect(captured.first.$2, equals('/ssh'));
    });

    // Test 5 : route inconnue → sensibilité normal par défaut
    test('route inconnue utilise la sensibilité normal par défaut', () {
      // D'abord aller sur critical pour avoir un changement potentiel
      observer.didPush(_fakeRoute('/settings'), _fakeRoute('/'));
      captured.clear();
      observer.didPush(_fakeRoute('/route-inconnue'), _fakeRoute('/settings'));
      expect(captured.length, equals(1));
      expect(captured.first.$1, equals(PageSensitivity.normal));
    });

    // Test 6 : pas de callback si la sensibilité ne change pas
    test('aucun callback si la sensibilité reste identique', () {
      // /ssh → sensitive
      observer.didPush(_fakeRoute('/ssh'), _fakeRoute('/'));
      captured.clear();
      // /info → aussi sensitive : pas de callback attendu
      observer.didPush(_fakeRoute('/info'), _fakeRoute('/ssh'));
      expect(captured, isEmpty);
      expect(observer.currentSensitivity, equals(PageSensitivity.sensitive));
    });

    // Test 7 : la map routeSensitivity contient toutes les routes attendues
    test('routeSensitivity contient toutes les routes attendues', () {
      expect(routeSensitivity.containsKey('/'), isTrue);
      expect(routeSensitivity.containsKey('/ssh'), isTrue);
      expect(routeSensitivity.containsKey('/wol'), isTrue);
      expect(routeSensitivity.containsKey('/info'), isTrue);
      expect(routeSensitivity.containsKey('/settings'), isTrue);
      expect(routeSensitivity.containsKey('/tailscale'), isTrue);
      expect(routeSensitivity.containsKey('/security'), isTrue);

      expect(routeSensitivity['/'], equals(PageSensitivity.normal));
      expect(routeSensitivity['/ssh'], equals(PageSensitivity.sensitive));
      expect(routeSensitivity['/wol'], equals(PageSensitivity.normal));
      expect(routeSensitivity['/info'], equals(PageSensitivity.sensitive));
      expect(routeSensitivity['/settings'], equals(PageSensitivity.critical));
      expect(routeSensitivity['/tailscale'], equals(PageSensitivity.sensitive));
      expect(routeSensitivity['/security'], equals(PageSensitivity.critical));
    });
  });
}
