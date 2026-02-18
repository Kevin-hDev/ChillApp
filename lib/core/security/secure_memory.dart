// =============================================================
// FIX-001 : Secure memory cleanup for secrets
// GAP-001 : PIN secrets in Dart memory (non-erasable immutable Strings)
// =============================================================
//
// PROBLEM : The PIN is an immutable Dart String. The GC copies
// objects in memory without zeroing them. The PIN persists
// as multiple copies in the heap.
//
// SOLUTION : Use Uint8List (mutable) instead of String
// to manipulate the PIN. Zero-out immediately after use.
// =============================================================

import 'dart:typed_data';

/// Secure wrapper for sensitive data in memory.
/// Uses Uint8List (mutable, zeroizable) instead of String (immutable).
///
/// Usage:
/// ```dart
/// final secret = SecureBytes.fromString(pin);
/// try {
///   // ... use secret.bytes for crypto operations ...
/// } finally {
///   secret.dispose(); // Guaranteed zeroing
/// }
/// ```
class SecureBytes {
  final Uint8List _data;
  bool _disposed = false;

  SecureBytes(int length) : _data = Uint8List(length);

  SecureBytes.fromList(List<int> data)
      : _data = Uint8List.fromList(data);

  /// Converts a String to Uint8List and handles it securely.
  /// The original String remains in memory (Dart limitation), but
  /// subsequent operations use the mutable Uint8List.
  SecureBytes.fromString(String value)
      : _data = Uint8List.fromList(value.codeUnits);

  /// Access the bytes. Throws if already disposed.
  Uint8List get bytes {
    if (_disposed) {
      throw StateError('SecureBytes: access after dispose is forbidden');
    }
    return _data;
  }

  int get length => _data.length;
  bool get isDisposed => _disposed;

  /// Deterministic zeroing of memory.
  /// Call in a finally block to guarantee cleanup.
  void dispose() {
    if (!_disposed) {
      // Write zeros over the entire length
      _data.fillRange(0, _data.length, 0);
      _disposed = true;
    }
  }
}

/// Extension on Uint8List for secure cleanup.
extension SecureUint8ListExtension on Uint8List {
  /// In-place zeroing of the content.
  void secureZero() {
    fillRange(0, length, 0);
  }
}

/// Constant-time comparison for Uint8List.
/// REQUIRED when comparing secrets (hash, salt, token).
/// The == operator short-circuits on the first difference,
/// revealing the divergence position via timing (CWE-208).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
