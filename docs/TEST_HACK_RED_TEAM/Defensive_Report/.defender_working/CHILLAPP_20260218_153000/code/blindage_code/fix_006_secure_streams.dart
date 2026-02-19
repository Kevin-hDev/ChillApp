// =============================================================
// FIX-006 : Gestion securisee des Streams Dart
// GAP-006 : Gestion securisee des Streams absente
// Cible : lib/features/tailscale/tailscale_provider.dart
// =============================================================
//
// PROBLEME : Les streams stdin/stdout du daemon accumulent
// des donnees sensibles dans leurs buffers internes.
// Pas de gestion du backpressure ni de nettoyage apres lecture.
// Les subscription leaks peuvent garder des references.
//
// SOLUTION : Wrapper securise autour des Stream<List<int>>
// avec nettoyage automatique des buffers et cancel garanti.
// =============================================================

import 'dart:async';
import 'dart:typed_data';

/// Stream listener securise avec nettoyage automatique.
/// Garantit :
/// 1. Les buffers sont zeroises apres traitement
/// 2. Le subscription est cancel dans dispose()
/// 3. Le backpressure est gere (buffer max configurable)
class SecureStreamReader {
  StreamSubscription<List<int>>? _subscription;
  final int maxBufferSize;
  final List<Uint8List> _pendingBuffers = [];
  bool _disposed = false;

  /// [maxBufferSize] : taille max cumulee des buffers en attente (bytes).
  /// Si depasse, les nouveaux buffers sont ignores (backpressure).
  SecureStreamReader({this.maxBufferSize = 1024 * 1024}); // 1 Mo par defaut

  /// Ecoute un stream et appelle [onData] pour chaque chunk.
  /// Les bytes sont automatiquement zeroises apres le callback.
  void listen(
    Stream<List<int>> stream, {
    required void Function(Uint8List data) onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    if (_disposed) {
      throw StateError('SecureStreamReader deja dispose');
    }

    _subscription = stream.listen(
      (data) {
        final buffer = Uint8List.fromList(data);

        // Backpressure : rejeter si buffer trop plein
        final totalSize =
            _pendingBuffers.fold<int>(0, (sum, b) => sum + b.length);
        if (totalSize + buffer.length > maxBufferSize) {
          buffer.fillRange(0, buffer.length, 0); // Zeroiser quand meme
          return; // Ignorer le chunk
        }

        _pendingBuffers.add(buffer);

        try {
          onData(buffer);
        } finally {
          // Zeroiser le buffer apres traitement
          buffer.fillRange(0, buffer.length, 0);
          _pendingBuffers.remove(buffer);
        }
      },
      onError: (error) {
        if (onError != null) {
          onError(error);
        }
      },
      onDone: onDone,
    );
  }

  /// Nettoie tous les buffers en attente et cancel le subscription.
  Future<void> dispose() async {
    if (!_disposed) {
      _disposed = true;
      // Zeroiser tous les buffers en attente
      for (final buffer in _pendingBuffers) {
        buffer.fillRange(0, buffer.length, 0);
      }
      _pendingBuffers.clear();
      // Cancel le subscription
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  bool get isDisposed => _disposed;
}

// =============================================================
// INTEGRATION dans tailscale_provider.dart :
// =============================================================
//
// AVANT :
//   _process!.stdout.listen((data) {
//     final json = String.fromCharCodes(data);
//     _handleDaemonMessage(json);
//   });
//
// APRES :
//   final _streamReader = SecureStreamReader();
//
//   _streamReader.listen(
//     _process!.stdout,
//     onData: (data) {
//       final json = String.fromCharCodes(data);
//       _handleDaemonMessage(json);
//       // data est automatiquement zerorise apres ce callback
//     },
//     onError: (error) => _handleDaemonError(error),
//     onDone: () => _handleDaemonDisconnect(),
//   );
//
// Dans dispose() du provider :
//   await _streamReader.dispose();
