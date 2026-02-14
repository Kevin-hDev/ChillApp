import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_provider.dart';

/// NOTE SECURITE : Le PIN est stocke dans SharedPreferences (texte clair sur disque).
/// PBKDF2 avec 100k iterations rend le brute force offline impraticable (~heures sur GPU).
/// Cependant, un attaquant avec acces au systeme de fichiers peut supprimer le hash
/// pour desactiver le lock. Le PIN protege contre l'utilisation occasionnelle,
/// pas contre un attaquant determine avec acces physique complet.
///
/// KNOWN LIMITATION (SE-PIN-011): Dart strings are immutable and managed by the GC,
/// so the PIN plaintext cannot be reliably zeroed from memory after use.
/// Mitigating this would require FFI (dart:ffi) with a native secure-memory
/// allocator, which is out of scope for the current threat model.
/// The PIN is only held in a local variable for the duration of hash computation.

class LockState {
  final bool isEnabled;
  final bool isUnlocked;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final bool isLoading;

  const LockState({
    this.isEnabled = false,
    this.isUnlocked = false,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.isLoading = false,
  });

  LockState copyWith({
    bool? isEnabled,
    bool? isUnlocked,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    bool? isLoading,
  }) {
    return LockState(
      isEnabled: isEnabled ?? this.isEnabled,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final lockProvider =
    NotifierProvider<LockNotifier, LockState>(LockNotifier.new);

class LockNotifier extends Notifier<LockState> {
  static const _pinHashKey = 'pin_hash';
  static const _pinSaltKey = 'pin_salt';
  static const _failedAttemptsKey = 'pin_failed_attempts';
  static const _lockedUntilKey = 'pin_locked_until';

  @override
  LockState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final hasPin = prefs.getString(_pinHashKey) != null;
    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final lockedUntilMs = prefs.getInt(_lockedUntilKey);
    final lockedUntil = lockedUntilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
        : null;
    return LockState(
      isEnabled: hasPin,
      failedAttempts: failedAttempts,
      lockedUntil: lockedUntil,
      isLoading: false,
    );
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// PBKDF2 avec HMAC-SHA256, 100 000 iterations
  Uint8List _pbkdf2(String password, String salt,
      {int iterations = 100000, int keyLength = 32}) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final saltBytes = utf8.encode(salt);
    var result = <int>[];
    var blockIndex = 1;

    while (result.length < keyLength) {
      // U1 = HMAC(password, salt || INT(blockIndex))
      final blockBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, blockIndex);
      var u = hmac.convert([...saltBytes, ...blockBytes]).bytes;
      var block = List<int>.from(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < block.length; j++) {
          block[j] ^= u[j];
        }
      }

      result.addAll(block);
      blockIndex++;
    }

    return Uint8List.fromList(result.sublist(0, keyLength));
  }

  String _hashPin(String pin, String salt) {
    final derived = _pbkdf2(pin, salt);
    return base64Encode(derived);
  }

  /// Constant-time string comparison to prevent timing attacks
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Ancien format SHA-256 pour migration
  String _hashPinLegacy(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  /// Calcul du delai de verrouillage avec backoff exponentiel.
  /// Pas de lock sous 5 tentatives, puis 30s, 60s, 120s, 240s, max 300s.
  int _lockDurationSeconds(int totalFailed) {
    if (totalFailed < 5) return 0;
    final level = (totalFailed ~/ 5); // 1, 2, 3, 4...
    final duration = 30 * (1 << (level - 1)); // 30, 60, 120, 240...
    return duration.clamp(30, 300); // plafonne a 5 minutes
  }

  Future<void> setPin(String pin) async {
    if (pin.length != 8 || !RegExp(r'^\d{8}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 8 digits');
    }
    final prefs = ref.read(sharedPrefsProvider);
    final salt = _generateSalt();
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setString(_pinHashKey, _hashPin(pin, salt));
    state = state.copyWith(isEnabled: true, isUnlocked: true);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = ref.read(sharedPrefsProvider);

    // Rate limiting : bloquer si en periode de verrouillage
    if (state.lockedUntil != null &&
        DateTime.now().isBefore(state.lockedUntil!)) {
      return false;
    }

    final stored = prefs.getString(_pinHashKey);
    if (stored == null) return false;

    final salt = prefs.getString(_pinSaltKey);
    bool match = false;

    // MIGRATION: Legacy hash formats are supported for backward compatibility:
    // - No salt (pre-v1): sha256(pin) → 64 char hex
    // - Salt + SHA-256 (v1): sha256('$salt:$pin') → 64 char hex
    // - Salt + PBKDF2 (v2, current): pbkdf2(pin, salt, 100k iter) → 44 char base64
    // Legacy formats are automatically migrated to v2 on successful verification.
    // TODO: Remove legacy migration in a future major version.
    if (salt != null && stored.length == 44) {
      // Nouveau format PBKDF2 (base64 = 44 chars)
      match = _constantTimeEquals(_hashPin(pin, salt), stored);
    } else if (salt != null && stored.length == 64) {
      // Ancien format SHA-256 avec sel (hex = 64 chars) : migration
      final legacyHash = _hashPinLegacy(pin, salt);
      if (_constantTimeEquals(legacyHash, stored)) {
        match = true;
        // Migrer vers PBKDF2
        await prefs.setString(_pinHashKey, _hashPin(pin, salt));
      }
    } else if (salt == null) {
      // Tres ancien format sans sel : migration
      final oldHash = sha256.convert(utf8.encode(pin)).toString();
      if (_constantTimeEquals(oldHash, stored)) {
        match = true;
        final newSalt = _generateSalt();
        await prefs.setString(_pinSaltKey, newSalt);
        await prefs.setString(_pinHashKey, _hashPin(pin, newSalt));
      }
    }

    if (match) {
      // Succes : remettre le compteur a zero
      state = state.copyWith(
        isUnlocked: true,
        failedAttempts: 0,
        clearLockedUntil: true,
      );
      await prefs.setInt(_failedAttemptsKey, 0);
      await prefs.remove(_lockedUntilKey);
      return true;
    } else {
      // Echec : incrementer et calculer le verrouillage
      final newAttempts = state.failedAttempts + 1;
      final lockSeconds = _lockDurationSeconds(newAttempts);
      DateTime? newLockedUntil;
      if (lockSeconds > 0) {
        newLockedUntil =
            DateTime.now().add(Duration(seconds: lockSeconds));
        await prefs.setInt(
            _lockedUntilKey, newLockedUntil.millisecondsSinceEpoch);
      }
      state = state.copyWith(
        failedAttempts: newAttempts,
        lockedUntil: newLockedUntil,
      );
      await prefs.setInt(_failedAttemptsKey, newAttempts);
      return false;
    }
  }

  Future<void> removePin() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(_pinHashKey);
    await prefs.remove(_pinSaltKey);
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockedUntilKey);
    state = state.copyWith(
      isEnabled: false,
      isUnlocked: true,
      failedAttempts: 0,
      clearLockedUntil: true,
    );
  }

  void lock() {
    state = state.copyWith(failedAttempts: 0, isUnlocked: false);
  }
}
