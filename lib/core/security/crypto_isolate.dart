import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// =============================================================
// FIX-003 : CryptoIsolate — PBKDF2 dans un Isolate séparé
// =============================================================
//
// Objectif : exécuter le calcul PBKDF2 dans un Isolate distinct
// pour isoler la mémoire crypto du main isolate et ne pas bloquer
// le thread UI pendant les 100 000 itérations.
//
// Après usage, les données dérivées sont zéroïsées en mémoire
// (best-effort : Dart ne garantit pas l'effacement GC, mais on
// minimise la fenêtre d'exposition).
// =============================================================

class _Pbkdf2Params {
  final List<int> passwordBytes;
  final List<int> saltBytes;
  final int iterations;
  final int keyLength;

  const _Pbkdf2Params({
    required this.passwordBytes,
    required this.saltBytes,
    required this.iterations,
    required this.keyLength,
  });
}

class CryptoIsolate {
  // Classe utilitaire — pas d'instanciation directe
  CryptoIsolate._();

  /// Calcule le hash PBKDF2 du PIN dans un Isolate séparé.
  /// Retourne une chaîne Base64 de 44 caractères.
  static Future<String> hashPinIsolated(String pin, String salt) async {
    final params = _Pbkdf2Params(
      passwordBytes: utf8.encode(pin),
      saltBytes: utf8.encode(salt),
      iterations: 100000,
      keyLength: 32,
    );
    final result = await Isolate.run(() => _computePbkdf2(params));
    return result;
  }

  /// Calcul PBKDF2 exécuté dans l'Isolate secondaire.
  /// Toutes les données sensibles sont zéroïsées après usage.
  static String _computePbkdf2(_Pbkdf2Params params) {
    final hmac = Hmac(sha256, params.passwordBytes);
    final saltBytes = params.saltBytes;
    var result = <int>[];
    var blockIndex = 1;

    while (result.length < params.keyLength) {
      // U1 = HMAC(password, salt || INT(blockIndex))
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

    // Zéroïser les données sensibles (best-effort)
    derived.fillRange(0, derived.length, 0);
    for (var i = 0; i < result.length; i++) {
      result[i] = 0;
    }

    return encoded;
  }
}
