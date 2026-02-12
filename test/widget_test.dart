import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chill_app/app.dart';

void main() {
  testWidgets('App loads dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ChillApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenue sur Chill'), findsOneWidget);
  });
}
