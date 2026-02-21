// =============================================================
// FIX-006 : Gestion sécurisée des Streams Dart
// GAP-006 : Gestion sécurisée des Streams absente
// Cible : lib/features/tailscale/tailscale_provider.dart
// =============================================================
//
// PROBLÈME : Les streams stdin/stdout du daemon accumulent
// des données sensibles dans leurs buffers internes.
// Pas de gestion du backpressure ni de nettoyage après lecture.
// Les subscription leaks peuvent garder des références.
//
// SOLUTION : Wrapper sécurisé autour des Stream<List<int>>
// avec nettoyage automatique des buffers et cancel garanti.
// =============================================================

import 'dart:async';
import 'dart:typed_data';

/// Stream listener sécurisé avec nettoyage automatique.
/// Garantit :
/// 1. Les buffers sont zéroïsés après traitement
/// 2. Le subscription est cancel dans dispose()
/// 3. Le backpressure est géré (buffer max configurable)
class SecureStreamReader {
  StreamSubscription<List<int>>? _subscription;
  final int maxBufferSize;
  final List<Uint8List> _pendingBuffers = [];
  bool _disposed = false;

  /// [maxBufferSize] : taille max cumulée des buffers en attente (bytes).
  /// Si dépassé, les nouveaux buffers sont ignorés (backpressure).
  SecureStreamReader({this.maxBufferSize = 1024 * 1024}); // 1 Mo par défaut

  /// Écoute un stream et appelle [onData] pour chaque chunk.
  /// Les bytes sont automatiquement zéroïsés après le callback.
  void listen(
    Stream<List<int>> stream, {
    required void Function(Uint8List data) onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    if (_disposed) {
      throw StateError('SecureStreamReader déjà disposé');
    }

    _subscription = stream.listen(
      (data) {
        final buffer = Uint8List.fromList(data);

        // Backpressure : rejeter si buffer trop plein
        final totalSize =
            _pendingBuffers.fold<int>(0, (sum, b) => sum + b.length);
        if (totalSize + buffer.length > maxBufferSize) {
          buffer.fillRange(0, buffer.length, 0); // Zéroïser quand même
          return; // Ignorer le chunk
        }

        _pendingBuffers.add(buffer);

        try {
          onData(buffer);
        } finally {
          // Zéroïser le buffer après traitement
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
      // Zéroïser tous les buffers en attente
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
