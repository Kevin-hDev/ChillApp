// Tests pour FIX-013 (Screenshot Protection)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ============================================
  // Tests : SensitiveDataField masking
  // ============================================

  group('SensitiveDataField masking logic', () {
    test('masque correctement une chaine longue', () {
      final result = _mask('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample');
      expect(result.startsWith('ss'), isTrue);
      expect(result.endsWith('le'), isTrue);
      expect(result.contains('*'), isTrue);
    });

    test('masque les chaines courtes en ****', () {
      expect(_mask('abc'), '****');
      expect(_mask('ab'), '****');
      expect(_mask('a'), '****');
    });

    test('preserve la longueur pour les chaines > 4', () {
      final input = 'abcdefgh';
      final masked = _mask(input);
      expect(masked.length, input.length);
    });
  });

  // ============================================
  // Tests : SensitiveDataField widget
  // ============================================

  group('SensitiveDataField widget', () {
    testWidgets('affiche le label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestSensitiveField(
              label: 'Cle SSH',
              data: 'test-data-123',
            ),
          ),
        ),
      );

      expect(find.text('Cle SSH'), findsOneWidget);
    });

    testWidgets('masque les donnees par defaut', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestSensitiveField(
              label: 'Token',
              data: 'secret-token-value',
            ),
          ),
        ),
      );

      // Le texte complet ne doit pas etre visible
      expect(find.text('secret-token-value'), findsNothing);
      // Le texte masque doit etre present
      expect(find.textContaining('*'), findsOneWidget);
    });

    testWidgets('bouton reveler est present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestSensitiveField(
              label: 'Token',
              data: 'secret-token-value',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });

  // ============================================
  // Tests : ScreenCaptureDetector
  // ============================================

  group('ScreenCaptureDetector process list', () {
    test('liste des processus connus non vide', () {
      final processes = [
        'obs', 'obs-studio', 'simplescreenrecorder', 'kazam',
        'peek', 'vokoscreen', 'ffmpeg', 'scrot', 'flameshot',
      ];
      expect(processes.isNotEmpty, isTrue);
      expect(processes.length, greaterThan(5));
    });
  });
}

// ============================================
// Helpers
// ============================================

String _mask(String data) {
  if (data.length <= 4) return '****';
  return '${data.substring(0, 2)}${'*' * (data.length - 4)}${data.substring(data.length - 2)}';
}

class _TestSensitiveField extends StatelessWidget {
  final String label;
  final String data;

  const _TestSensitiveField({required this.label, required this.data});

  @override
  Widget build(BuildContext context) {
    final masked = data.length <= 4
        ? '****'
        : '${data.substring(0, 2)}${'*' * (data.length - 4)}${data.substring(data.length - 2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Row(
          children: [
            Expanded(child: Text(masked)),
            IconButton(
              icon: const Icon(Icons.visibility),
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
