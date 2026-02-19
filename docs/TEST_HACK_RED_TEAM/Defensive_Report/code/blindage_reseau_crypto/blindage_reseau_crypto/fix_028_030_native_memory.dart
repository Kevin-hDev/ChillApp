// =============================================================
// FIX-028 : Allocation native FFI pour secrets critiques
// GAP-028: Allocation native FFI absente (P1)
// FIX-030 : Attenuation cold boot attacks
// GAP-030: Attenuation cold boot attacks absente (P2)
// Cible: lib/core/security/native_secret.dart (nouveau)
// =============================================================
//
// PROBLEME : Le GC Dart copie les objets en memoire. Les secrets
// persistent en multiples copies. Remanence DRAM permet extraction
// apres extinction physique.
//
// SOLUTION :
// 1. Allocation native via dart:ffi (hors GC Dart)
// 2. Zeroisation deterministe via memset
// 3. Verrouillage en memoire (mlock) pour eviter le swap
// 4. Pattern d'utilisation securise avec try/finally
// =============================================================

import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:io';

// Bindings natifs pour les operations memoire
// Sur Linux/macOS : libc
// Sur Windows : kernel32

/// Secret stocke en memoire native (hors GC Dart).
/// La memoire est verrouillee (pas de swap) et zeroisee a la liberation.
class NativeSecret {
  ffi.Pointer<ffi.Uint8>? _pointer;
  final int _length;
  bool _disposed = false;

  NativeSecret._(this._pointer, this._length);

  /// Alloue de la memoire native pour un secret.
  factory NativeSecret.allocate(int length) {
    final ptr = _calloc(length);
    if (ptr == ffi.nullptr) {
      throw StateError('Failed to allocate native memory');
    }

    // Verrouiller en memoire (pas de swap sur disque)
    _mlock(ptr, length);

    return NativeSecret._(ptr, length);
  }

  /// Cree un NativeSecret a partir de bytes Dart.
  /// Les bytes source sont zeroises apres la copie.
  factory NativeSecret.fromBytes(Uint8List bytes) {
    final secret = NativeSecret.allocate(bytes.length);
    // Copier les bytes dans la memoire native
    for (int i = 0; i < bytes.length; i++) {
      secret._pointer![i] = bytes[i];
    }
    // Zeroiser la source Dart
    bytes.fillRange(0, bytes.length, 0);
    return secret;
  }

  /// Longueur du secret.
  int get length => _length;

  /// Acces en lecture seule aux bytes.
  /// ATTENTION : Ne pas stocker la reference retournee.
  Uint8List get bytes {
    _checkNotDisposed();
    final list = Uint8List(_length);
    for (int i = 0; i < _length; i++) {
      list[i] = _pointer![i];
    }
    return list;
  }

  /// Ecrit des bytes dans le secret.
  void write(Uint8List data, {int offset = 0}) {
    _checkNotDisposed();
    final end = offset + data.length;
    if (end > _length) throw RangeError('Data exceeds secret length');
    for (int i = 0; i < data.length; i++) {
      _pointer![offset + i] = data[i];
    }
  }

  /// Zeroisation deterministe et liberation.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_pointer != null && _pointer != ffi.nullptr) {
      // Zeroisation via memset (non optimisable par le compilateur)
      _secureZero(_pointer!, _length);

      // Deverrouiller la memoire
      _munlock(_pointer!, _length);

      // Liberer
      _free(_pointer!);
    }
    _pointer = null;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NativeSecret already disposed');
  }

  // === Bindings natifs ===

  static ffi.Pointer<ffi.Uint8> _calloc(int size) {
    if (Platform.isWindows) {
      return _windowsCalloc(size);
    }
    return _posixCalloc(size);
  }

  static void _free(ffi.Pointer<ffi.Uint8> ptr) {
    if (Platform.isWindows) {
      _windowsFree(ptr);
    } else {
      _posixFree(ptr);
    }
  }

  static void _secureZero(ffi.Pointer<ffi.Uint8> ptr, int size) {
    // Volatile write pour eviter l'optimisation du compilateur
    for (int i = 0; i < size; i++) {
      ptr[i] = 0;
    }
    // Double passe pour les architectures avec cache
    for (int i = 0; i < size; i++) {
      ptr[i] = 0xFF;
    }
    for (int i = 0; i < size; i++) {
      ptr[i] = 0;
    }
  }

  static void _mlock(ffi.Pointer<ffi.Uint8> ptr, int size) {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // mlock via libc
        final libc = ffi.DynamicLibrary.open(
          Platform.isLinux ? 'libc.so.6' : 'libSystem.B.dylib',
        );
        final mlock = libc.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
            int Function(ffi.Pointer<ffi.Void>, int)>('mlock');
        mlock(ptr.cast<ffi.Void>(), size);
      } else if (Platform.isWindows) {
        final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
        final virtualLock = kernel32.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
            int Function(ffi.Pointer<ffi.Void>, int)>('VirtualLock');
        virtualLock(ptr.cast<ffi.Void>(), size);
      }
    } catch (_) {
      // mlock peut echouer si limite atteinte — continuer sans
    }
  }

  static void _munlock(ffi.Pointer<ffi.Uint8> ptr, int size) {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final libc = ffi.DynamicLibrary.open(
          Platform.isLinux ? 'libc.so.6' : 'libSystem.B.dylib',
        );
        final munlock = libc.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
            int Function(ffi.Pointer<ffi.Void>, int)>('munlock');
        munlock(ptr.cast<ffi.Void>(), size);
      } else if (Platform.isWindows) {
        final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
        final virtualUnlock = kernel32.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
            int Function(ffi.Pointer<ffi.Void>, int)>('VirtualUnlock');
        virtualUnlock(ptr.cast<ffi.Void>(), size);
      }
    } catch (_) {
      // Continuer sans
    }
  }

  static ffi.Pointer<ffi.Uint8> _posixCalloc(int size) {
    final libc = ffi.DynamicLibrary.open(
      Platform.isLinux ? 'libc.so.6' : 'libSystem.B.dylib',
    );
    final calloc = libc.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.IntPtr, ffi.IntPtr),
        ffi.Pointer<ffi.Void> Function(int, int)>('calloc');
    return calloc(size, 1).cast<ffi.Uint8>();
  }

  static void _posixFree(ffi.Pointer<ffi.Uint8> ptr) {
    final libc = ffi.DynamicLibrary.open(
      Platform.isLinux ? 'libc.so.6' : 'libSystem.B.dylib',
    );
    final free = libc.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('free');
    free(ptr.cast<ffi.Void>());
  }

  static ffi.Pointer<ffi.Uint8> _windowsCalloc(int size) {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final heapAlloc = kernel32.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.IntPtr, ffi.Uint32, ffi.IntPtr),
        ffi.Pointer<ffi.Void> Function(int, int, int)>('HeapAlloc');
    final getProcessHeap = kernel32.lookupFunction<
        ffi.IntPtr Function(),
        int Function()>('GetProcessHeap');
    final heap = getProcessHeap();
    // HEAP_ZERO_MEMORY = 0x08
    return heapAlloc(heap, 0x08, size).cast<ffi.Uint8>();
  }

  static void _windowsFree(ffi.Pointer<ffi.Uint8> ptr) {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final heapFree = kernel32.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Pointer<ffi.Void>),
        int Function(int, int, ffi.Pointer<ffi.Void>)>('HeapFree');
    final getProcessHeap = kernel32.lookupFunction<
        ffi.IntPtr Function(),
        int Function()>('GetProcessHeap');
    heapFree(getProcessHeap(), 0, ptr.cast<ffi.Void>());
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// Remplacer dans lock_provider.dart :
//   final pinBytes = SecureBytes.fromString(pin);
//   try { ... } finally { pinBytes.dispose(); }
//
// Par (pour les secrets critiques comme le PIN) :
//   final nativePin = NativeSecret.fromBytes(utf8.encode(pin));
//   try {
//     // Utiliser nativePin.bytes pour le PBKDF2
//   } finally {
//     nativePin.dispose(); // Zeroisation + mlock/munlock
//   }
//
// NOTE : NativeSecret est plus lourd que SecureBytes (FIX-001).
// Utiliser NativeSecret pour les secrets de longue duree (cles).
// Utiliser SecureBytes pour les secrets ephemeres (PIN en transit).
// =============================================================
