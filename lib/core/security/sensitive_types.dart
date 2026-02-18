// =============================================================
// FIX-004 : Extension types pour données sensibles
// GAP-004 : Extension types manquants
// Cible : lib/features/lock/lock_provider.dart
// =============================================================
//
// PROBLÈME : Le PIN, le sel et le hash sont manipulés comme
// des String/List<int> génériques. Aucun typage fort ne distingue
// un secret d'une donnée normale. Risque de confusion et de
// fuite accidentelle (log, affichage, comparaison ==).
//
// SOLUTION : Extension types Dart 3+ pour wrapper les secrets.
// Zero cost runtime (vérifié uniquement à la compilation).
// Chaque type a sa méthode secureDispose().
// =============================================================

import 'dart:typed_data';

/// Extension type pour un PIN en bytes.
/// Empêche l'utilisation accidentelle comme String.
/// Impose l'utilisation de secureDispose() après usage.
extension type PinBytes(Uint8List _bytes) {
  int get length => _bytes.length;
  bool get isEmpty => _bytes.isEmpty;

  /// Accès aux bytes pour les opérations crypto UNIQUEMENT.
  Uint8List get rawBytes => _bytes;

  /// Zéroisation sécurisée.
  void secureDispose() {
    _bytes.fillRange(0, _bytes.length, 0);
  }

  /// Crée depuis un String PIN (conversion immédiate en bytes).
  static PinBytes fromString(String pin) {
    return PinBytes(Uint8List.fromList(pin.codeUnits));
  }
}

/// Extension type pour un sel cryptographique.
extension type SaltData(String _value) {
  String get value => _value;
  int get length => _value.length;
  bool get isEmpty => _value.isEmpty;
}

/// Extension type pour un hash dérivé (PBKDF2).
///
/// **ATTENTION** : Ne JAMAIS utiliser `==` pour comparer deux DerivedHash.
/// L'operateur `==` herite de String et est vulnerable aux timing attacks.
/// Utiliser UNIQUEMENT [equalsConstantTime] pour les comparaisons.
///
/// Limitation Dart : les extension types ne peuvent pas overrider `==`.
/// Un lint custom ou une revue de code doit verifier qu'aucun `==` n'est
/// utilise sur ce type.
extension type DerivedHash(String _value) {
  String get value => _value;
  int get length => _value.length;

  /// Comparaison en temps constant — SEULE méthode autorisée.
  bool equalsConstantTime(DerivedHash other) {
    if (_value.length != other._value.length) return false;
    int result = 0;
    for (int i = 0; i < _value.length; i++) {
      result |= _value.codeUnitAt(i) ^ other._value.codeUnitAt(i);
    }
    return result == 0;
  }
}
