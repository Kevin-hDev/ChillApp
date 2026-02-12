import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chill_app/app.dart';

void main() {
  testWidgets('App loads dashboard', (WidgetTester tester) async {
    // Surface plus grande pour éviter les overflow en test
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(child: ChillApp()),
    );
    // pump au lieu de pumpAndSettle car l'animation du fond tourne en boucle
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Bienvenue sur Chill'), findsOneWidget);
  });
}
