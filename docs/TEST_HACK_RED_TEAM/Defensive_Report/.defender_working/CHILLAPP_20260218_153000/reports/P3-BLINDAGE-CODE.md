# P3 — Blindage du Code Dart (Runtime)

**Projet** : ChillApp
**Date** : 18 fevrier 2026
**Entree** : P2_reinforcement_points.yaml (7 gaps assignes a P3)
**Knowledge** : dart-runtime-hardening.md (18 sections evaluees)

---

## Synthese

**7 gaps traites. 7 fichiers de code ecrits. 7 fichiers de test ecrits.**

Chaque fix est un fichier Dart complet et integrable dans le dossier `lib/core/security/`.

---

## Code Ecrit

| Fix | Gap | Fichier | Test | Priorite |
|-----|-----|---------|------|----------|
| FIX-001 | GAP-001 | fix_001_secure_memory.dart | test_fix_001.dart | P0 |
| FIX-002 | GAP-002 | fix_002_secure_error_handling.dart | test_fix_002.dart | P1 |
| FIX-003 | GAP-003 | fix_003_crypto_isolate.dart | test_fix_003.dart | P2 |
| FIX-004 | GAP-004 | fix_004_sensitive_types.dart | test_fix_004.dart | P2 |
| FIX-005 | GAP-005 | fix_005_sealed_security_states.dart | test_fix_005.dart | P3 |
| FIX-006 | GAP-006 | fix_006_secure_streams.dart | test_fix_006.dart | P3 |
| FIX-007 | GAP-007 | fix_007_nonce_manager.dart | test_fix_007.dart | P2 |

---

## Detail des Protections

### FIX-001 : Nettoyage securise de la memoire (P0)

**Probleme** : Le PIN est un `String` Dart immutable. Le GC copie les objets sans les zeroiser. Le PIN persiste en multiples copies.

**Solution** : Classe `SecureBytes` qui utilise `Uint8List` (mutable) avec zeroisation via `fillRange(0, length, 0)` dans un bloc `finally`.

**Integration** : `lib/core/security/secure_memory.dart`
```dart
final pinBytes = SecureBytes.fromString(pin);
try {
  // ... operations crypto ...
} finally {
  pinBytes.dispose(); // Zeroisation garantie
}
```

---

### FIX-002 : Error handling securise (P1)

**Probleme** : `runApp()` direct sans zone de capture. Les erreurs fuient des stack traces avec chemins et info sensibles.

**Solution** : `SecureErrorHandler` avec `runZonedGuarded` + `FlutterError.onError` + sanitisation des messages.

**Integration** : Modifier `lib/main.dart`
```dart
SecureErrorHandler.initialize();
SecureErrorHandler.runSecureApp(ProviderScope(...));
```

---

### FIX-003 : Isolation crypto dans un Isolate (P2)

**Probleme** : PBKDF2 (100k iterations) dans le main isolate. Dump memoire = extraction des secrets.

**Solution** : `CryptoIsolate.hashPinIsolated()` execute le PBKDF2 dans un `Isolate.run()` separe. La memoire de l'isolate est liberee a sa fin.

**Integration** : Remplacer `_pbkdf2()` synchrone par `CryptoIsolate.hashPinIsolated()` async.

---

### FIX-004 : Extension types pour donnees sensibles (P2)

**Probleme** : PIN, sel et hash manipules comme `String`/`List<int>` generiques. Confusion possible.

**Solution** : `PinBytes`, `SaltData`, `DerivedHash` — types compile-time zero cost. `DerivedHash.equalsConstantTime()` remplace `_constantTimeEquals()`.

---

### FIX-005 : Sealed classes pour etats securite (P3)

**Probleme** : Etats geres par `bool`/`enum` sans exhaustivite. Etat ambigu possible.

**Solution** : `sealed class LockSecurityState` + `sealed class DaemonConnectionState`. Le compilateur force le traitement de chaque cas.

---

### FIX-006 : Gestion securisee des Streams (P3)

**Probleme** : Streams stdin/stdout du daemon sans nettoyage des buffers ni backpressure.

**Solution** : `SecureStreamReader` avec zeroisation automatique des buffers apres traitement, gestion du backpressure, et cancel garanti.

---

### FIX-007 : Gestionnaire de nonces AES-GCM (P2)

**Probleme** : Prerequis pour le chiffrement IPC (P5). Reutiliser un nonce = compromission du chiffrement.

**Solution** : `NonceManager` avec compteur + aleatoire. Limite NIST 2^32 operations. Alerte `needsRekey` a 90%. `SecureRandom` centralise la generation aleatoire.

---

## Structure de Fichiers a Creer

```
lib/core/security/
  secure_memory.dart          <-- FIX-001 (SecureBytes, constantTimeEquals)
  secure_error_handler.dart   <-- FIX-002 (runZonedGuarded, sanitisation)
  crypto_isolate.dart         <-- FIX-003 (PBKDF2 dans Isolate)
  sensitive_types.dart        <-- FIX-004 (PinBytes, SaltData, DerivedHash)
  security_states.dart        <-- FIX-005 (LockSecurityState, DaemonConnectionState)
  secure_streams.dart         <-- FIX-006 (SecureStreamReader)
  nonce_manager.dart          <-- FIX-007 (NonceManager, SecureRandom)
```

---

## Couverture des 18 Sections Knowledge

| # | Section | Statut |
|---|---------|--------|
| 1 | Comparaison temps constant | Existant (PROT-003) + renforce (FIX-001) |
| 2 | Generation aleatoire | Existant (PROT-001) + wrapper (FIX-007) |
| 3 | Nonce AES-GCM | **FIX-007** |
| 4 | Dart Isolates | **FIX-003** |
| 5 | Extension Types | **FIX-004** |
| 6 | Sealed Classes | **FIX-005** |
| 7 | GC et secrets | **FIX-001** |
| 8 | Zone error handling | **FIX-002** |
| 9 | Streams securises | **FIX-006** |
| 10 | Dart FFI security | Differe P5 (GAP-028) |
| 11 | IPv4 parsing | Couvert par Dart 3.10 |
| 12 | Build Hooks | N/A (pas de code natif) |
| 13 | pub.dev publication | N/A (pas un package) |
| 14 | Sockets Unix Windows | Differe P5 (GAP-035) |
| 15 | dart pub cache gc | N/A (CI/CD) |
| 16 | GC proprietes | Informationnelle |
| 17 | GC probleme secrets | **FIX-001** |
| 18 | dart:ffi tension | Differe P5 (GAP-028) |

**Score** : 10/18 sections couvertes (56%) → +39% par rapport a P1 (17%)

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
