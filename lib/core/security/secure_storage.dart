// =============================================================
// FIX-027 : Migration from SharedPreferences to secure storage
// GAP-027: SharedPreferences stores PIN hash/salt in plain text (P0)
// =============================================================
//
// PROBLEM: SharedPreferences stores the PIN hash, salt, and rate limiting
// data as plain JSON readable by any process.
// Deleting the file = disabling the lock.
//
// SOLUTION:
// 1. Multi-OS abstraction for secure storage
// 2. Windows: Credential Manager (DPAPI via PSCredential XML)
// 3. Linux: libsecret (GNOME Keyring / KWallet via secret-tool)
// 4. macOS: Keychain (via security CLI)
// 5. Encrypted fallback if keystore is unavailable
//
// No new dependencies: uses only dart:io, dart:convert, package:crypto
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ---------------------------------------------------------------------------
// Abstract backend interface
// ---------------------------------------------------------------------------

/// Multi-platform secure storage abstraction.
/// Uses the native OS keystore when available.
abstract class SecureStorageBackend {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<bool> containsKey(String key);
}

// ---------------------------------------------------------------------------
// Linux backend (secret-tool / libsecret)
// ---------------------------------------------------------------------------

/// Linux implementation via secret-tool (libsecret).
/// Requires: libsecret-tools package (secret-tool binary).
class LinuxSecureStorage implements SecureStorageBackend {
  static const String _serviceName = 'chillapp';

  @override
  Future<void> write(String key, String value) async {
    // secret-tool reads the secret from stdin
    final proc = await Process.start('secret-tool', [
      'store',
      '--label=$_serviceName:$key',
      'service', _serviceName,
      'key', key,
    ]);
    proc.stdin.write(value);
    await proc.stdin.close();
    await proc.exitCode;
  }

  @override
  Future<String?> read(String key) async {
    final result = await Process.run('secret-tool', [
      'lookup',
      'service', _serviceName,
      'key', key,
    ]);
    if (result.exitCode != 0) return null;
    final value = result.stdout.toString();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> delete(String key) async {
    await Process.run('secret-tool', [
      'clear',
      'service', _serviceName,
      'key', key,
    ]);
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

// ---------------------------------------------------------------------------
// Windows backend (DPAPI via PSCredential XML)
// ---------------------------------------------------------------------------

/// Windows implementation via PowerShell Credential Manager (DPAPI).
class WindowsSecureStorage implements SecureStorageBackend {
  static const String _target = 'ChillApp';

  /// Regex de validation des cles : lettres, chiffres, underscore, tiret.
  /// Empeche l'injection PowerShell via des cles malveillantes.
  static final RegExp _validKey = RegExp(r'^[a-zA-Z0-9_-]+$');

  static void _validateKey(String key) {
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError(
        'Cle SecureStorage invalide: "$key" (caracteres autorises: a-z, A-Z, 0-9, _, -)',
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _validateKey(key);
    // Encode the value so it survives PowerShell string interpolation
    final encoded = base64Encode(utf8.encode(value));
    await Process.run('powershell', [
      '-NonInteractive',
      '-Command',
      r'$dir = "$env:LOCALAPPDATA\ChillApp"; '
          r'if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }; '
          '[System.Management.Automation.PSCredential]::new('
          '"$_target:$key", '
          '(ConvertTo-SecureString "$encoded" -AsPlainText -Force)'
          r') | Export-Clixml -Path "$env:LOCALAPPDATA\ChillApp\cred_$key.xml"',
    ]);
  }

  @override
  Future<String?> read(String key) async {
    _validateKey(key);
    final result = await Process.run('powershell', [
      '-NonInteractive',
      '-Command',
      r'try { $cred = Import-Clixml -Path '
          r'"$env:LOCALAPPDATA\ChillApp\cred_$key.xml"; '
          r'$cred.GetNetworkCredential().Password } catch { "" }',
    ]);
    if (result.exitCode != 0) return null;
    final encoded = result.stdout.toString().trim();
    if (encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    _validateKey(key);
    await Process.run('powershell', [
      '-NonInteractive',
      '-Command',
      r'Remove-Item -Path "$env:LOCALAPPDATA\ChillApp\cred_$key.xml" '
          '-ErrorAction SilentlyContinue',
    ]);
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

// ---------------------------------------------------------------------------
// macOS backend (Keychain via security CLI)
// ---------------------------------------------------------------------------

/// macOS implementation via security CLI (Keychain).
class MacOSSecureStorage implements SecureStorageBackend {
  static const String _service = 'com.chill.chillapp';

  @override
  Future<void> write(String key, String value) async {
    // Delete the old value first to avoid duplicate errors
    await delete(key);
    await Process.run('security', [
      'add-generic-password',
      '-s', _service,
      '-a', key,
      '-w', value,
      '-T', '', // No access by other apps
    ]);
  }

  @override
  Future<String?> read(String key) async {
    final result = await Process.run('security', [
      'find-generic-password',
      '-s', _service,
      '-a', key,
      '-w',
    ]);
    if (result.exitCode != 0) return null;
    final value = result.stdout.toString().trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> delete(String key) async {
    await Process.run('security', [
      'delete-generic-password',
      '-s', _service,
      '-a', key,
    ]);
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

// ---------------------------------------------------------------------------
// Fallback backend (XOR cipher derived from machine ID)
// ---------------------------------------------------------------------------

/// Fallback: local encryption with a key derived from the machine ID.
/// Used when no native keystore is available.
/// WARNING: Less secure than native keystores — the key is tied
/// to the machine ID, which is readable on disk.
class FallbackSecureStorage implements SecureStorageBackend {
  final File _storageFile;
  final Uint8List _derivedKey;
  Map<String, String> _data = {};

  FallbackSecureStorage._(this._storageFile, this._derivedKey);

  static Future<FallbackSecureStorage> create(String storagePath) async {
    final file = File(storagePath);

    // Derive a key from machine-specific factors
    final machineId = await _getMachineId();
    final key = sha256.convert(utf8.encode(machineId)).bytes;

    final storage = FallbackSecureStorage._(file, Uint8List.fromList(key));
    await storage._load();
    return storage;
  }

  static Future<String> _getMachineId() async {
    if (Platform.isLinux) {
      try {
        final id = await File('/etc/machine-id').readAsString();
        return id.trim();
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run(
          'ioreg',
          ['-rd1', '-c', 'IOPlatformExpertDevice'],
        );
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final match = RegExp(r'IOPlatformUUID" = "([^"]+)"')
              .firstMatch(output);
          if (match != null) return match.group(1)!;
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NonInteractive',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystemProduct).UUID',
        ]);
        if (result.exitCode == 0) {
          final id = result.stdout.toString().trim();
          if (id.isNotEmpty) return id;
        }
      } catch (_) {}
    }
    // Final fallback
    return 'chillapp-${Platform.operatingSystem}-fallback-key';
  }

  Future<void> _load() async {
    if (!await _storageFile.exists()) return;
    try {
      final encrypted = await _storageFile.readAsString();
      final decrypted = _xorCipher(base64Decode(encrypted));
      _data = Map<String, String>.from(
        jsonDecode(utf8.decode(decrypted)) as Map,
      );
    } catch (_) {
      _data = {};
    }
  }

  Future<void> _save() async {
    final plaintext = utf8.encode(jsonEncode(_data));
    final encrypted = _xorCipher(Uint8List.fromList(plaintext));
    await _storageFile.writeAsString(base64Encode(encrypted));
  }

  Uint8List _xorCipher(Uint8List data) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ _derivedKey[i % _derivedKey.length];
    }
    return result;
  }

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
    await _save();
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
    await _save();
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

// ---------------------------------------------------------------------------
// SecureStorage factory
// ---------------------------------------------------------------------------

/// Factory to obtain the correct backend for the current OS.
///
/// Usage:
/// ```dart
/// final storage = await SecureStorage.getInstance();
/// await storage.write('pin_hash', hash);
/// final hash = await storage.read('pin_hash');
/// await storage.delete('pin_hash');
/// final exists = await storage.containsKey('pin_hash');
/// ```
class SecureStorage {
  static SecureStorageBackend? _instance;

  /// Returns the singleton backend instance, initializing it on first call.
  static Future<SecureStorageBackend> getInstance() async {
    if (_instance != null) return _instance!;

    if (Platform.isLinux) {
      // Check if secret-tool is available on this system
      final check = await Process.run('which', ['secret-tool']);
      if (check.exitCode == 0) {
        _instance = LinuxSecureStorage();
      }
    } else if (Platform.isWindows) {
      _instance = WindowsSecureStorage();
    } else if (Platform.isMacOS) {
      _instance = MacOSSecureStorage();
    }

    // Fallback if no native backend is available
    if (_instance == null) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      _instance = await FallbackSecureStorage.create(
        '$home/.chillapp_secure.dat',
      );
    }

    return _instance!;
  }

  /// Resets the singleton — intended for testing only.
  static void resetForTesting() {
    _instance = null;
  }
}
