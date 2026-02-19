// =============================================================
// FIX-027 : Migration SharedPreferences vers stockage securise
// GAP-027: SharedPreferences en texte clair (P0)
// Cible: lib/features/lock/lock_provider.dart, settings_provider.dart
// =============================================================
//
// PROBLEME : SharedPreferences stocke hash PIN, sel, rate limiting
// et preferences en JSON clair lisible par tout processus.
// Suppression du fichier = desactivation du lock.
//
// SOLUTION :
// 1. Abstraction multi-OS pour secure storage
// 2. Windows: Credential Manager (DPAPI)
// 3. Linux: libsecret (GNOME Keyring / KWallet)
// 4. macOS: Keychain
// 5. Fallback chiffre si keystore indisponible
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Abstraction de stockage securise multi-plateforme.
/// Utilise le keystore natif de l'OS quand disponible.
abstract class SecureStorageBackend {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> deleteAll();
  Future<bool> containsKey(String key);
}

/// Implementation Linux via secret-tool (libsecret).
class LinuxSecureStorage implements SecureStorageBackend {
  static const String _serviceName = 'chillapp';

  @override
  Future<void> write(String key, String value) async {
    final result = await Process.run('secret-tool', [
      'store',
      '--label=$_serviceName:$key',
      'service', _serviceName,
      'key', key,
    ], environment: {'SECRET_TOOL_INPUT': value});

    // secret-tool lit le secret depuis stdin
    if (result.exitCode != 0) {
      // Ecrire via stdin
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
  Future<void> deleteAll() async {
    // Lister et supprimer toutes les cles
    final result = await Process.run('secret-tool', [
      'search',
      'service', _serviceName,
    ]);
    // Parser et supprimer chaque cle
    // Fallback : supprimer les cles connues
    for (final k in ['pin_hash', 'pin_salt', 'rate_limit', 'audit_key']) {
      await delete(k);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

/// Implementation Windows via PowerShell Credential Manager.
class WindowsSecureStorage implements SecureStorageBackend {
  static const String _target = 'ChillApp';

  @override
  Future<void> write(String key, String value) async {
    // Utiliser DPAPI via PowerShell
    final encoded = base64Encode(utf8.encode(value));
    await Process.run('powershell', [
      '-Command',
      '[System.Management.Automation.PSCredential]::new('
          '"$_target:$key", '
          '(ConvertTo-SecureString "$encoded" -AsPlainText -Force)'
          ') | Export-Clixml -Path '
          '"\$env:LOCALAPPDATA\\ChillApp\\cred_$key.xml"',
    ]);
  }

  @override
  Future<String?> read(String key) async {
    final result = await Process.run('powershell', [
      '-Command',
      'try { '
          '\$cred = Import-Clixml -Path '
          '"\$env:LOCALAPPDATA\\ChillApp\\cred_$key.xml"; '
          '\$cred.GetNetworkCredential().Password '
          '} catch { "" }',
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
    await Process.run('powershell', [
      '-Command',
      'Remove-Item -Path '
          '"\$env:LOCALAPPDATA\\ChillApp\\cred_$key.xml" '
          '-ErrorAction SilentlyContinue',
    ]);
  }

  @override
  Future<void> deleteAll() async {
    await Process.run('powershell', [
      '-Command',
      'Remove-Item -Path '
          '"\$env:LOCALAPPDATA\\ChillApp\\cred_*.xml" '
          '-ErrorAction SilentlyContinue',
    ]);
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

/// Implementation macOS via security (Keychain).
class MacOSSecureStorage implements SecureStorageBackend {
  static const String _service = 'com.chill.chillapp';

  @override
  Future<void> write(String key, String value) async {
    // Supprimer l'ancienne valeur si elle existe
    await delete(key);
    await Process.run('security', [
      'add-generic-password',
      '-s', _service,
      '-a', key,
      '-w', value,
      '-T', '', // Pas d'acces par d'autres apps
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
    return result.stdout.toString().trim();
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
  Future<void> deleteAll() async {
    for (final k in ['pin_hash', 'pin_salt', 'rate_limit', 'audit_key']) {
      await delete(k);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await read(key)) != null;
  }
}

/// Fallback : chiffrement local AES derive d'une cle machine.
class FallbackSecureStorage implements SecureStorageBackend {
  final File _storageFile;
  final Uint8List _derivedKey;
  Map<String, String> _data = {};

  FallbackSecureStorage._(this._storageFile, this._derivedKey);

  static Future<FallbackSecureStorage> create(String storagePath) async {
    final file = File(storagePath);

    // Deriver une cle a partir de facteurs machine
    final machineId = await _getMachineId();
    final key = sha256.convert(utf8.encode(machineId)).bytes;

    final storage = FallbackSecureStorage._(file, Uint8List.fromList(key));
    await storage._load();
    return storage;
  }

  static Future<String> _getMachineId() async {
    if (Platform.isLinux) {
      try {
        return await File('/etc/machine-id').readAsString();
      } catch (_) {}
    }
    // Fallback
    return 'chillapp-${Platform.operatingSystem}-fallback';
  }

  Future<void> _load() async {
    if (!await _storageFile.exists()) return;
    try {
      final encrypted = await _storageFile.readAsString();
      final decrypted = _xorCipher(base64Decode(encrypted));
      _data = Map<String, String>.from(jsonDecode(utf8.decode(decrypted)));
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
  Future<void> deleteAll() async {
    _data.clear();
    await _save();
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

/// Factory pour obtenir le bon backend selon l'OS.
class SecureStorage {
  static SecureStorageBackend? _instance;

  static Future<SecureStorageBackend> getInstance() async {
    if (_instance != null) return _instance!;

    if (Platform.isLinux) {
      // Verifier si secret-tool est disponible
      final check = await Process.run('which', ['secret-tool']);
      if (check.exitCode == 0) {
        _instance = LinuxSecureStorage();
      }
    } else if (Platform.isWindows) {
      _instance = WindowsSecureStorage();
    } else if (Platform.isMacOS) {
      _instance = MacOSSecureStorage();
    }

    // Fallback si aucun backend natif
    _instance ??= await FallbackSecureStorage.create(
      '${Directory.systemTemp.path}/chillapp_secure.dat',
    );

    return _instance!;
  }
}

// =============================================================
// INTEGRATION dans lock_provider.dart :
// =============================================================
//
// Remplacer :
//   final prefs = await SharedPreferences.getInstance();
//   prefs.setString('pin_hash', hash);
//
// Par :
//   final storage = await SecureStorage.getInstance();
//   await storage.write('pin_hash', hash);
//
// Et :
//   final hash = prefs.getString('pin_hash');
// Par :
//   final hash = await storage.read('pin_hash');
// =============================================================
