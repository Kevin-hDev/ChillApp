// Test pour FIX-006 : Gestion sécurisée des Streams
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/secure_streams.dart';

void main() {
  group('SecureStreamReader', () {
    test('lit les données du stream correctement', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      final received = <List<int>>[];

      reader.listen(
        controller.stream,
        onData: (data) {
          received.add(List<int>.from(data)); // Copie avant zéroïsation
        },
      );

      controller.add([1, 2, 3]);
      await Future.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received[0], equals([1, 2, 3]));

      await reader.dispose();
      await controller.close();
    });

    test('dispose cancel le subscription', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      var count = 0;

      reader.listen(
        controller.stream,
        onData: (data) => count++,
      );

      controller.add([1]);
      await Future.delayed(Duration.zero);
      expect(count, equals(1));

      await reader.dispose();

      controller.add([2]); // Ne devrait pas être reçu
      await Future.delayed(Duration.zero);
      expect(count, equals(1)); // Toujours 1

      await controller.close();
    });

    test('respecte le backpressure maxBufferSize', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader(maxBufferSize: 10);
      var receivedCount = 0;

      reader.listen(
        controller.stream,
        onData: (data) => receivedCount++,
      );

      // 5 bytes : sous la limite
      controller.add(List.filled(5, 0));
      await Future.delayed(Duration.zero);
      expect(receivedCount, equals(1));

      // Buffer libéré après traitement, on peut en envoyer d'autres
      controller.add(List.filled(5, 0));
      await Future.delayed(Duration.zero);
      expect(receivedCount, equals(2));

      await reader.dispose();
      await controller.close();
    });

    test('lève une StateError si utilisé après dispose', () async {
      final controller = StreamController<List<int>>.broadcast();
      final reader = SecureStreamReader();
      await reader.dispose();

      expect(
        () => reader.listen(controller.stream, onData: (_) {}),
        throwsStateError,
      );

      await controller.close();
    });

    test('isDisposed reflète l état correctement', () async {
      final reader = SecureStreamReader();
      expect(reader.isDisposed, isFalse);
      await reader.dispose();
      expect(reader.isDisposed, isTrue);
    });

    test('double dispose ne lève pas d exception', () async {
      final reader = SecureStreamReader();
      await reader.dispose();
      expect(() async => reader.dispose(), returnsNormally);
    });

    test('zéroïse le buffer après traitement', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      Uint8List? capturedBuffer;

      reader.listen(
        controller.stream,
        onData: (data) {
          capturedBuffer = data; // Référence AVANT zéroïsation (dans le callback)
        },
      );

      controller.add([10, 20, 30]);
      await Future.delayed(Duration.zero);

      // Après le callback, le buffer doit être zéroïsé
      expect(capturedBuffer, isNotNull);
      expect(capturedBuffer!.every((b) => b == 0), isTrue);

      await reader.dispose();
      await controller.close();
    });

    test('propage les erreurs via onError', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      Object? caughtError;

      reader.listen(
        controller.stream,
        onData: (_) {},
        onError: (error) => caughtError = error,
      );

      controller.addError(Exception('erreur test'));
      await Future.delayed(Duration.zero);

      expect(caughtError, isA<Exception>());

      await reader.dispose();
      await controller.close();
    });

    test('appelle onDone quand le stream se ferme', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      var doneCalled = false;

      reader.listen(
        controller.stream,
        onData: (_) {},
        onDone: () => doneCalled = true,
      );

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(doneCalled, isTrue);
      await reader.dispose();
    });

    test('maxBufferSize par défaut est 1 Mo', () {
      final reader = SecureStreamReader();
      expect(reader.maxBufferSize, equals(1024 * 1024));
    });
  });
}
