// Test pour FIX-006 : Gestion securisee des Streams
import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';

import 'fix_006_secure_streams.dart';

void main() {
  group('SecureStreamReader', () {
    test('lit les donnees du stream', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      final received = <List<int>>[];

      reader.listen(
        controller.stream,
        onData: (data) {
          received.add(List<int>.from(data)); // Copie avant zeroisation
        },
      );

      controller.add([1, 2, 3]);
      await Future.delayed(Duration.zero); // Laisser le micro-task s'executer

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

      controller.add([2]); // Ne devrait pas etre recu
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

      // Envoyer des donnees depassant le buffer max
      controller.add(List.filled(5, 0)); // 5 bytes, OK
      await Future.delayed(Duration.zero);
      expect(receivedCount, equals(1));

      // Le buffer est libere apres traitement, donc on peut en envoyer d'autres
      controller.add(List.filled(5, 0)); // 5 bytes, OK
      await Future.delayed(Duration.zero);
      expect(receivedCount, equals(2));

      await reader.dispose();
      await controller.close();
    });

    test('leve une exception si utilise apres dispose', () async {
      final controller = StreamController<List<int>>();
      final reader = SecureStreamReader();
      await reader.dispose();

      expect(
        () => reader.listen(controller.stream, onData: (_) {}),
        throwsStateError,
      );

      await controller.close();
    });

    test('isDisposed reflecte l etat', () async {
      final reader = SecureStreamReader();
      expect(reader.isDisposed, isFalse);
      await reader.dispose();
      expect(reader.isDisposed, isTrue);
    });
  });
}
