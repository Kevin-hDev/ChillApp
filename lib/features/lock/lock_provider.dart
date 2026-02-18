import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_provider.dart';
import '../../core/security/secure_storage.dart';
import '../../core/security/crypto_isolate.dart';

// =============================================================
// SECURITY NOTES
// =============================================================
//
// FIX-027: PIN hash and salt are now stored in the OS native
// keystore (Linux: libsecret, Windows: DPAPI, macOS: Keychain)
// via SecureStorage. SharedPreferences is retained ONLY for
// non-sensitive data: failed attempts counter and lock timestamp.
//
// FALLBACK: If SecureStorage fails (keystore unavailable),
// the code falls back to SharedPreferences with a warning in
// the debug console. This degrades gracefully rather than
// crashing the app.
//
// MIGRATION: On first use, if pin_hash / pin_salt exist in
// SharedPreferences (legacy), they are automatically copied
// to SecureStorage and removed from SharedPreferences.
//
// KNOWN LIMITATION (SE-PIN-011): Dart strings are immutable
// and managed by the GC, so the PIN plaintext cannot be
// reliably zeroed from memory after use. The PIN is only
// held in a local variable for the duration of hash computation.
// =============================================================

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
  // Keys stored in SecureStorage (sensitive)
  static const _pinHashKey = 'pin_hash';
  static const _pinSaltKey = 'pin_salt';

  // Keys kept in SharedPreferences (non-sensitive rate limiting data)
  static const _failedAttemptsKey = 'pin_failed_attempts';
  static const _lockedUntilKey = 'pin_locked_until';

  @override
  LockState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final lockedUntilMs = prefs.getInt(_lockedUntilKey);
    final lockedUntil = lockedUntilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
        : null;

    // We cannot do async work in build(), so we schedule a migration check
    // and a PIN presence check after the first frame.
    // isEnabled defaults to false until _initAsync() completes.
    Future.microtask(_initAsync);

    return LockState(
      isEnabled: false,
      failedAttempts: failedAttempts,
      lockedUntil: lockedUntil,
      isLoading: true,
    );
  }

  // -------------------------------------------------------------------------
  // Initialisation async : migration + check PIN existence
  // -------------------------------------------------------------------------

  Future<void> _initAsync() async {
    // 1. Migrate legacy SharedPreferences data to SecureStorage
    await _migrateLegacyPrefsToSecureStorage();

    // 2. Check if a PIN is configured in SecureStorage
    final hasPin = await _secureContainsKey(_pinHashKey);

    state = state.copyWith(isEnabled: hasPin, isLoading: false);
  }

  /// Migrates pin_hash and pin_salt from SharedPreferences to SecureStorage
  /// if they are present there (one-time migration from pre-FIX-027 versions).
  Future<void> _migrateLegacyPrefsToSecureStorage() async {
    final prefs = ref.read(sharedPrefsProvider);
    final legacyHash = prefs.getString(_pinHashKey);
    final legacySalt = prefs.getString(_pinSaltKey);

    if (legacyHash == null) return; // Nothing to migrate

    debugPrint(
      '[LockNotifier] Migrating PIN from SharedPreferences to SecureStorage...',
    );

    try {
      final storage = await SecureStorage.getInstance();
      await storage.write(_pinHashKey, legacyHash);
      if (legacySalt != null) {
        await storage.write(_pinSaltKey, legacySalt);
      }
      // Remove from SharedPreferences once migration succeeds
      await prefs.remove(_pinHashKey);
      await prefs.remove(_pinSaltKey);
      debugPrint('[LockNotifier] Migration completed successfully.');
    } catch (e) {
      // Migration failed: leave SharedPreferences data intact as fallback
      debugPrint('[LockNotifier] Migration failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // SecureStorage helpers with SharedPreferences fallback
  // -------------------------------------------------------------------------

  Future<void> _secureWrite(String key, String value) async {
    try {
      final storage = await SecureStorage.getInstance();
      await storage.write(key, value);
    } catch (e) {
      debugPrint('[LockNotifier] SecureStorage.write failed ($key): $e');
      debugPrint('[LockNotifier] WARN: Falling back to SharedPreferences.');
      final prefs = ref.read(sharedPrefsProvider);
      await prefs.setString(key, value);
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      final storage = await SecureStorage.getInstance();
      final value = await storage.read(key);
      if (value != null) return value;
    } catch (e) {
      debugPrint('[LockNotifier] SecureStorage.read failed ($key): $e');
      debugPrint('[LockNotifier] WARN: Falling back to SharedPreferences.');
    }
    // Fallback to SharedPreferences (includes legacy unmigrted data)
    final prefs = ref.read(sharedPrefsProvider);
    return prefs.getString(key);
  }

  Future<void> _secureDelete(String key) async {
    try {
      final storage = await SecureStorage.getInstance();
      await storage.delete(key);
    } catch (e) {
      debugPrint('[LockNotifier] SecureStorage.delete failed ($key): $e');
    }
    // Always clean SharedPreferences too (covers fallback and migration leftovers)
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(key);
  }

  Future<bool> _secureContainsKey(String key) async {
    try {
      final storage = await SecureStorage.getInstance();
      if (await storage.containsKey(key)) return true;
    } catch (e) {
      debugPrint('[LockNotifier] SecureStorage.containsKey failed ($key): $e');
    }
    // Check SharedPreferences as well (fallback / migration in progress)
    final prefs = ref.read(sharedPrefsProvider);
    return prefs.getString(key) != null;
  }

  // -------------------------------------------------------------------------
  // Crypto helpers
  // -------------------------------------------------------------------------

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// PBKDF2 with HMAC-SHA256, 100 000 iterations.
  /// Conservé pour les tests unitaires et la migration de hashes legacy
  /// qui pourraient en avoir besoin via un accès externe futur.
  // ignore: unused_element
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

  Future<String> _hashPin(String pin, String salt) async {
    return await CryptoIsolate.hashPinIsolated(pin, salt);
  }

  /// Constant-time string comparison to prevent timing attacks (CWE-208)
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Legacy SHA-256 format for migration of old PINs
  String _hashPinLegacy(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  /// Lock duration with exponential backoff.
  /// No lock under 5 attempts, then 30s, 60s, 120s, 240s, max 300s.
  int _lockDurationSeconds(int totalFailed) {
    if (totalFailed < 5) return 0;
    final level = (totalFailed ~/ 5); // 1, 2, 3, 4...
    final duration = 30 * (1 << (level - 1)); // 30, 60, 120, 240...
    return duration.clamp(30, 300); // capped at 5 minutes
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  Future<void> setPin(String pin) async {
    if (pin.length != 8 || !RegExp(r'^\d{8}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 8 digits');
    }
    final salt = _generateSalt();
    final hash = await _hashPin(pin, salt);

    // Store in SecureStorage (with SharedPreferences fallback)
    await _secureWrite(_pinSaltKey, salt);
    await _secureWrite(_pinHashKey, hash);

    state = state.copyWith(isEnabled: true, isUnlocked: true, isLoading: false);
  }

  Future<bool> verifyPin(String pin) async {
    // Rate limiting: block if currently in a lockout period
    if (state.lockedUntil != null &&
        DateTime.now().isBefore(state.lockedUntil!)) {
      return false;
    }

    final stored = await _secureRead(_pinHashKey);
    if (stored == null) return false;

    final salt = await _secureRead(_pinSaltKey);
    bool match = false;

    // MIGRATION: Legacy hash formats are supported for backward compatibility:
    // - No salt (pre-v1): sha256(pin) → 64 char hex
    // - Salt + SHA-256 (v1): sha256('$salt:$pin') → 64 char hex
    // - Salt + PBKDF2 (v2, current): pbkdf2(pin, salt, 100k iter) → 44 char base64
    // Legacy formats are automatically migrated to v2 on successful verification.
    if (salt != null && stored.length == 44) {
      // Current PBKDF2 format (base64 = 44 chars)
      match = _constantTimeEquals(await _hashPin(pin, salt), stored);
    } else if (salt != null && stored.length == 64) {
      // Legacy SHA-256 with salt (hex = 64 chars): migrate on success
      final legacyHash = _hashPinLegacy(pin, salt);
      if (_constantTimeEquals(legacyHash, stored)) {
        match = true;
        // Migrate to PBKDF2 in SecureStorage
        await _secureWrite(_pinHashKey, await _hashPin(pin, salt));
      }
    } else if (salt == null) {
      // Very old format without salt: migrate on success
      final oldHash = sha256.convert(utf8.encode(pin)).toString();
      if (_constantTimeEquals(oldHash, stored)) {
        match = true;
        final newSalt = _generateSalt();
        await _secureWrite(_pinSaltKey, newSalt);
        await _secureWrite(_pinHashKey, await _hashPin(pin, newSalt));
      }
    }

    final prefs = ref.read(sharedPrefsProvider);

    if (match) {
      // Success: reset the counter (in SharedPreferences — non-sensitive)
      state = state.copyWith(
        isUnlocked: true,
        failedAttempts: 0,
        clearLockedUntil: true,
      );
      await prefs.setInt(_failedAttemptsKey, 0);
      await prefs.remove(_lockedUntilKey);
      return true;
    } else {
      // Failure: increment and compute lockout (in SharedPreferences — non-sensitive)
      final newAttempts = state.failedAttempts + 1;
      final lockSeconds = _lockDurationSeconds(newAttempts);
      DateTime? newLockedUntil;
      if (lockSeconds > 0) {
        newLockedUntil = DateTime.now().add(Duration(seconds: lockSeconds));
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
    // Remove sensitive data from SecureStorage
    await _secureDelete(_pinHashKey);
    await _secureDelete(_pinSaltKey);

    // Remove non-sensitive rate limiting data from SharedPreferences
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockedUntilKey);

    state = state.copyWith(
      isEnabled: false,
      isUnlocked: true,
      failedAttempts: 0,
      clearLockedUntil: true,
      isLoading: false,
    );
  }

  void lock() {
    state = state.copyWith(failedAttempts: 0, isUnlocked: false);
  }
}
