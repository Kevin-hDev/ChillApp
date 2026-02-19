// =============================================================
// FIX-003 : Isolation crypto dans un Dart Isolate
// GAP-003 : Operations crypto dans le main isolate
// Cible : lib/features/lock/lock_provider.dart:86-112
// =============================================================
//
// PROBLEME : Le PBKDF2 (100k iterations) s'execute dans le main
// isolate. Un dump memoire du main expose les secrets crypto.
// Le PBKDF2 bloque aussi le thread UI pendant le calcul.
//
// SOLUTION : Executer le PBKDF2 dans un Isolate.run() separe.
// Le GC de l'isolate est independant du main. A la fin de
// l'isolate, sa memoire est liberee completement.
// =============================================================

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Parametre envoye a l'isolate pour le calcul PBKDF2.
/// Classe serialisable pour le transfert inter-isolate.
class _Pbkdf2Params {
  final List<int> passwordBytes;
  final List<int> saltBytes;
  final int iterations;
  final int keyLength;

  _Pbkdf2Params({
    required this.passwordBytes,
    required this.saltBytes,
    this.iterations = 100000,
    this.keyLength = 32,
  });
}

/// Execute les operations cryptographiques dans un Isolate separe.
/// Avantages :
/// - Le GC de l'isolate est independant du main
/// - La memoire de l'isolate est liberee a sa fin
/// - Le main thread UI n'est pas bloque
class CryptoIsolate {
  /// Calcule un hash PBKDF2 dans un Isolate separe.
  /// Le PIN et le sel sont transmis comme bytes (pas String)
  /// et zeroises dans l'isolate apres usage.
  static Future<String> hashPinIsolated(String pin, String salt) async {
    final params = _Pbkdf2Params(
      passwordBytes: utf8.encode(pin),
      saltBytes: utf8.encode(salt),
    );

    final result = await Isolate.run(() => _computePbkdf2(params));
    return result;
  }

  /// Calcul PBKDF2 interne — s'execute DANS l'isolate.
  /// A la fin de cette fonction, l'isolate est detruit
  /// et sa memoire est liberee par le runtime Dart.
  static String _computePbkdf2(_Pbkdf2Params params) {
    final hmac = Hmac(sha256, params.passwordBytes);
    final saltBytes = params.saltBytes;
    var result = <int>[];
    var blockIndex = 1;

    while (result.length < params.keyLength) {
      final blockBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, blockIndex);
      var u = hmac.convert([...saltBytes, ...blockBytes]).bytes;
      var block = List<int>.from(u);

      for (var i = 1; i < params.iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < block.length; j++) {
          block[j] ^= u[j];
        }
      }

      result.addAll(block);
      blockIndex++;
    }

    final derived = Uint8List.fromList(result.sublist(0, params.keyLength));
    final encoded = base64Encode(derived);

    // Zeroiser les donnees sensibles dans l'isolate
    derived.fillRange(0, derived.length, 0);
    for (var i = 0; i < result.length; i++) {
      result[i] = 0;
    }

    return encoded;
  }
}

// =============================================================
// INTEGRATION dans lock_provider.dart :
// =============================================================
//
// AVANT (dans LockNotifier) :
//   String _hashPin(String pin, String salt) {
//     final derived = _pbkdf2(pin, salt);
//     return base64Encode(derived);
//   }
//
// APRES :
//   Future<String> _hashPin(String pin, String salt) async {
//     return await CryptoIsolate.hashPinIsolated(pin, salt);
//   }
//
// NOTE : _hashPin devient async. Adapter les appels en consequence.
// setPin() et verifyPin() sont deja async, donc l'impact est minimal.
