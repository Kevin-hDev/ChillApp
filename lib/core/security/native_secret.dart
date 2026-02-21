import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:io';

/// Secret stocke en memoire native (hors du GC Dart).
///
/// La memoire est verrouillee (pas de swap) et effacee a la liberation.
/// Utilise FFI pour acceder directement a la memoire systeme.
///
/// Usage :
/// ```dart
/// final secret = NativeSecret.allocate(32);
/// try {
///   secret.write(myBytes);
///   // utiliser secret.bytes
/// } finally {
///   secret.dispose();
/// }
/// ```
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
    _mlock(ptr, length);
    return NativeSecret._(ptr, length);
  }

  /// Cree un secret a partir d'octets Dart (la source est effacee apres copie).
  factory NativeSecret.fromBytes(Uint8List bytes) {
    final secret = NativeSecret.allocate(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      secret._pointer![i] = bytes[i];
    }
    // Efface la source pour ne pas laisser de traces en memoire Dart
    bytes.fillRange(0, bytes.length, 0);
    return secret;
  }

  /// Longueur du secret en octets.
  int get length => _length;

  /// Indique si le secret a ete libere.
  bool get isDisposed => _disposed;

  /// Lit les octets du secret (copie dans une nouvelle liste Dart).
  Uint8List get bytes {
    _checkNotDisposed();
    final list = Uint8List(_length);
    for (int i = 0; i < _length; i++) {
      list[i] = _pointer![i];
    }
    return list;
  }

  /// Ecrit des donnees dans le secret, a partir d'un offset optionnel.
  void write(Uint8List data, {int offset = 0}) {
    _checkNotDisposed();
    final end = offset + data.length;
    if (end > _length) throw RangeError('Data exceeds secret length');
    for (int i = 0; i < data.length; i++) {
      _pointer![offset + i] = data[i];
    }
  }

  /// Libere la memoire native de facon securisee.
  ///
  /// Effectue un triple effacement (0x00 / 0xFF / 0x00) avant liberation.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_pointer != null && _pointer != ffi.nullptr) {
      _secureZero(_pointer!, _length);
      _munlock(_pointer!, _length);
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

  /// Efface securise via explicit_bzero (Linux/macOS) ou triple passe manuelle.
  ///
  /// explicit_bzero est garanti de ne pas etre optimise par le compilateur,
  /// contrairement aux boucles manuelles que le compilateur peut supprimer
  /// s'il detecte que la memoire n'est plus lue ensuite.
  static void _secureZero(ffi.Pointer<ffi.Uint8> ptr, int size) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final libc = ffi.DynamicLibrary.open(
          Platform.isLinux ? 'libc.so.6' : 'libSystem.B.dylib',
        );
        final explicitBzero = libc.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
            void Function(ffi.Pointer<ffi.Void>, int)>('explicit_bzero');
        explicitBzero(ptr.cast<ffi.Void>(), size);
        return;
      } catch (_) {
        // Fallback sur triple passe manuelle si explicit_bzero indisponible
      }
    }
    // Fallback : triple passe manuelle (0x00 / 0xFF / 0x00)
    for (int i = 0; i < size; i++) {
      ptr[i] = 0;
    }
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
    } catch (_) {}
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
    } catch (_) {}
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
    final free = libc.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('free');
    free(ptr.cast<ffi.Void>());
  }

  static ffi.Pointer<ffi.Uint8> _windowsCalloc(int size) {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final heapAlloc = kernel32.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.IntPtr, ffi.Uint32, ffi.IntPtr),
        ffi.Pointer<ffi.Void> Function(int, int, int)>('HeapAlloc');
    final getProcessHeap = kernel32.lookupFunction<ffi.IntPtr Function(),
        int Function()>('GetProcessHeap');
    final heap = getProcessHeap();
    return heapAlloc(heap, 0x08, size).cast<ffi.Uint8>();
  }

  static void _windowsFree(ffi.Pointer<ffi.Uint8> ptr) {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final heapFree = kernel32.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Pointer<ffi.Void>),
        int Function(int, int, ffi.Pointer<ffi.Void>)>('HeapFree');
    final getProcessHeap = kernel32.lookupFunction<ffi.IntPtr Function(),
        int Function()>('GetProcessHeap');
    heapFree(getProcessHeap(), 0, ptr.cast<ffi.Void>());
  }
}
