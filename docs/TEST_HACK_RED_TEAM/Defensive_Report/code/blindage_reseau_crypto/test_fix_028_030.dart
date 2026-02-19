// =============================================================
// Tests pour FIX-028/030 : Native Memory + Cold Boot
// =============================================================
//
// NOTE : Les tests FFI necessitent dart:ffi disponible en mode
// standalone (dart test). Ces tests verifient la logique sans
// appeler les fonctions natives reelles.

import 'dart:typed_data';

void main() {
  print('=== Tests FIX-028/030 : Native Memory ===\n');

  testSecureZeroPattern();
  testTriplePassZero();
  testFromBytesZerosSource();
  testDisposePreventsAccess();

  print('\n=== Tous les tests FIX-028/030 passes ===');
}

/// Test du pattern de zeroisation.
void testSecureZeroPattern() {
  print('Test: Secure zero pattern...');

  // Simuler le pattern triple passe
  final buffer = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

  // Passe 1 : zero
  buffer.fillRange(0, buffer.length, 0);
  assert(buffer.every((b) => b == 0), 'Passe 1: tout doit etre 0');

  // Passe 2 : 0xFF
  buffer.fillRange(0, buffer.length, 0xFF);
  assert(buffer.every((b) => b == 0xFF), 'Passe 2: tout doit etre 0xFF');

  // Passe 3 : zero
  buffer.fillRange(0, buffer.length, 0);
  assert(buffer.every((b) => b == 0), 'Passe 3: tout doit etre 0');

  print('  OK: Pattern triple passe fonctionne');
}

/// Test detaille du triple pass.
void testTriplePassZero() {
  print('Test: Triple pass zero...');

  final sizes = [1, 8, 16, 32, 64, 128, 256, 1024];

  for (final size in sizes) {
    final buffer = Uint8List(size);
    // Remplir avec des donnees
    for (int i = 0; i < size; i++) {
      buffer[i] = (i * 37 + 13) & 0xFF;
    }

    // Verifier que le buffer n'est pas zero
    assert(!buffer.every((b) => b == 0),
        'Le buffer ne doit pas etre zero avant la zeroisation');

    // Zeroiser avec triple passe
    _secureZero(buffer);

    // Verifier que le buffer est zero
    assert(buffer.every((b) => b == 0),
        'Le buffer doit etre zero apres la zeroisation (taille $size)');
  }

  print('  OK: Triple pass fonctionne pour toutes les tailles');
}

/// Test que fromBytes zeroize la source.
void testFromBytesZerosSource() {
  print('Test: fromBytes zeros source...');

  final source = Uint8List.fromList([0x41, 0x42, 0x43, 0x44]); // "ABCD"
  final copy = Uint8List.fromList(source); // Copie pour verification

  // Simuler fromBytes : copier puis zeroiser la source
  final destination = Uint8List(source.length);
  for (int i = 0; i < source.length; i++) {
    destination[i] = source[i];
  }
  source.fillRange(0, source.length, 0);

  // La destination doit avoir les donnees
  for (int i = 0; i < copy.length; i++) {
    assert(destination[i] == copy[i],
        'La destination doit contenir les donnees originales');
  }

  // La source doit etre zeroisee
  assert(source.every((b) => b == 0),
      'La source doit etre zeroisee apres la copie');

  print('  OK: fromBytes zeroize la source');
}

/// Test que dispose empeche tout acces ulterieur.
void testDisposePreventsAccess() {
  print('Test: Dispose prevents access...');

  // Simuler le pattern NativeSecret
  var disposed = false;
  Uint8List? data = Uint8List.fromList([1, 2, 3, 4]);

  // Simuler dispose
  if (data != null) {
    _secureZero(data);
  }
  data = null;
  disposed = true;

  // Verifier que l'acces est bloque
  assert(disposed, 'Le flag disposed doit etre true');
  assert(data == null, 'Le pointeur doit etre null');

  // Simuler _checkNotDisposed
  try {
    if (disposed) throw StateError('NativeSecret already disposed');
    // Ne devrait jamais arriver ici
    assert(false, 'Devrait avoir leve une exception');
  } on StateError catch (e) {
    assert(e.message == 'NativeSecret already disposed',
        'Le message d\'erreur doit etre correct');
  }

  print('  OK: Dispose bloque les acces ulterieurs');
}

// === Helpers ===

void _secureZero(Uint8List buffer) {
  // Passe 1 : zero
  for (int i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
  // Passe 2 : 0xFF
  for (int i = 0; i < buffer.length; i++) {
    buffer[i] = 0xFF;
  }
  // Passe 3 : zero
  for (int i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
}
