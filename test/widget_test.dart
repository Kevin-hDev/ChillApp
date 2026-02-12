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
    await tester.pumpAndSettle();

    expect(find.text('Bienvenue sur Chill'), findsOneWidget);
  });
}
