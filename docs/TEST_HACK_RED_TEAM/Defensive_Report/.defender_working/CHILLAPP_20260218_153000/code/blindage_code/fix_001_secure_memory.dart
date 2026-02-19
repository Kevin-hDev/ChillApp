// =============================================================
// FIX-001 : Nettoyage securise de la memoire pour les secrets
// GAP-001 : Secrets PIN en memoire Dart non effacables
// Cible : lib/features/lock/lock_provider.dart
// =============================================================
//
// PROBLEME : Le PIN est un String Dart immutable. Le GC copie
// les objets en memoire sans les zeroiser. Le PIN persiste
// en multiples copies dans le heap.
//
// SOLUTION : Utiliser Uint8List (mutable) au lieu de String
// pour manipuler le PIN. Zeroiser immediatement apres usage.
// Pour les secrets critiques, allocation FFI hors du GC.
// =============================================================

import 'dart:typed_data';

/// Wrapper securise pour les donnees sensibles en memoire.
/// Utilise Uint8List (mutable, zerosisable) au lieu de String (immutable).
///
/// Usage :
/// ```dart
/// final secret = SecureBytes.fromString(pin);
/// try {
///   // ... utiliser secret.bytes pour les operations crypto ...
/// } finally {
///   secret.dispose(); // Zeroisation garantie
/// }
/// ```
class SecureBytes {
  Uint8List _data;
  bool _disposed = false;

  SecureBytes(int length) : _data = Uint8List(length);

  SecureBytes.fromList(List<int> data)
      : _data = Uint8List.fromList(data);

  /// Convertit un String en Uint8List et le manipule de maniere securisee.
  /// Le String original reste en memoire (limitation Dart), mais les
  /// operations subsequentes utilisent le Uint8List mutable.
  SecureBytes.fromString(String value)
      : _data = Uint8List.fromList(value.codeUnits);

  /// Acces aux bytes. Leve une exception si deja dispose.
  Uint8List get bytes {
    if (_disposed) {
      throw StateError('SecureBytes: acces apres dispose interdit');
    }
    return _data;
  }

  int get length => _data.length;
  bool get isDisposed => _disposed;

  /// Zeroisation deterministe de la memoire.
  /// Appeler dans un bloc finally pour garantir le nettoyage.
  void dispose() {
    if (!_disposed) {
      // Ecriture de zeros sur toute la longueur
      _data.fillRange(0, _data.length, 0);
      _disposed = true;
    }
  }
}

/// Extension sur Uint8List pour le nettoyage securise.
extension SecureUint8ListExtension on Uint8List {
  /// Zeroisation in-place du contenu.
  void secureZero() {
    fillRange(0, length, 0);
  }
}

/// Comparaison en temps constant pour Uint8List.
/// OBLIGATOIRE pour comparer des secrets (hash, sel, token).
/// L'operateur == fait un court-circuit a la premiere difference,
/// revelant la position de la divergence via le timing (CWE-208).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int result = 0;
  for (int i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
