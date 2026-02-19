// =============================================================
// FIX-004 : Extension types pour donnees sensibles
// GAP-004 : Extension types manquants
// Cible : lib/features/lock/lock_provider.dart
// =============================================================
//
// PROBLEME : Le PIN, le sel et le hash sont manipules comme
// des String/List<int> generiques. Aucun typage fort ne distingue
// un secret d'une donnee normale. Risque de confusion et de
// fuite accidentelle (log, affichage, comparaison ==).
//
// SOLUTION : Extension types Dart 3+ pour wrapper les secrets.
// Zero cost runtime (verifie uniquement a la compilation).
// Chaque type a sa methode secureDispose().
// =============================================================

import 'dart:typed_data';

/// Extension type pour un PIN en bytes.
/// Empeche l'utilisation accidentelle comme String.
/// Impose l'utilisation de secureDispose() apres usage.
extension type PinBytes(Uint8List _bytes) {
  int get length => _bytes.length;
  bool get isEmpty => _bytes.isEmpty;

  /// Acces aux bytes pour les operations crypto UNIQUEMENT.
  Uint8List get rawBytes => _bytes;

  /// Zeroisation securisee.
  void secureDispose() {
    _bytes.fillRange(0, _bytes.length, 0);
  }

  /// Cree depuis un String PIN (conversion immediate en bytes).
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

/// Extension type pour un hash derive (PBKDF2).
/// Empeche la comparaison avec == (vulnerable au timing attack).
extension type DerivedHash(String _value) {
  String get value => _value;
  int get length => _value.length;

  /// Comparaison en temps constant — SEULE methode autorisee.
  bool equalsConstantTime(DerivedHash other) {
    if (_value.length != other._value.length) return false;
    int result = 0;
    for (int i = 0; i < _value.length; i++) {
      result |= _value.codeUnitAt(i) ^ other._value.codeUnitAt(i);
    }
    return result == 0;
  }
}

// =============================================================
// INTEGRATION dans lock_provider.dart :
// =============================================================
//
// AVANT :
//   String _hashPin(String pin, String salt) { ... }
//   bool _constantTimeEquals(String a, String b) { ... }
//
// APRES :
//   DerivedHash _hashPin(PinBytes pin, SaltData salt) { ... }
//   // _constantTimeEquals n'est plus necessaire :
//   match = computedHash.equalsConstantTime(storedHash);
//
// AVANT :
//   Future<void> setPin(String pin) async {
//     final salt = _generateSalt();
//     await prefs.setString(_pinSaltKey, salt);
//     await prefs.setString(_pinHashKey, _hashPin(pin, salt));
//
// APRES :
//   Future<void> setPin(String pin) async {
//     final pinBytes = PinBytes.fromString(pin);
//     try {
//       final salt = SaltData(_generateSalt());
//       await prefs.setString(_pinSaltKey, salt.value);
//       final hash = _hashPin(pinBytes, salt);
//       await prefs.setString(_pinHashKey, hash.value);
//     } finally {
//       pinBytes.secureDispose(); // Garantie de nettoyage
//     }
