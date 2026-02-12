import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockState {
  final bool isEnabled;
  final bool isUnlocked;
  final int failedAttempts;

  const LockState({
    this.isEnabled = false,
    this.isUnlocked = false,
    this.failedAttempts = 0,
  });

  LockState copyWith({
    bool? isEnabled,
    bool? isUnlocked,
    int? failedAttempts,
  }) {
    return LockState(
      isEnabled: isEnabled ?? this.isEnabled,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
    );
  }
}

final lockProvider =
    NotifierProvider<LockNotifier, LockState>(LockNotifier.new);

class LockNotifier extends Notifier<LockState> {
  static const _pinHashKey = 'pin_hash';

  @override
  LockState build() {
    _load();
    return const LockState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPin = prefs.getString(_pinHashKey) != null;
    state = state.copyWith(isEnabled: hasPin);
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinHashKey, _hashPin(pin));
    state = state.copyWith(isEnabled: true, isUnlocked: true);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinHashKey);
    if (stored == null) return false;

    if (_hashPin(pin) == stored) {
      state = state.copyWith(isUnlocked: true, failedAttempts: 0);
      return true;
    } else {
      state = state.copyWith(failedAttempts: state.failedAttempts + 1);
      return false;
    }
  }

  Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinHashKey);
    state = state.copyWith(isEnabled: false, isUnlocked: true, failedAttempts: 0);
  }

  void lock() {
    state = state.copyWith(isUnlocked: false, failedAttempts: 0);
  }
}
