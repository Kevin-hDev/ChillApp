# Guide d'Integration du Code — ChillApp

**Date** : 18 fevrier 2026
**Session** : CHILLAPP_20260218_153000

---

## Pre-requis

### Versions requises
- Flutter >= 3.38.7
- Dart >= 3.10.7
- Go >= 1.22 (pour le daemon)

### Dependances existantes (pas de nouvelles dependances)

Toutes les protections sont ecrites en Dart pur. Les packages deja presents suffisent :
- `package:crypto` (SHA-256, HMAC) — deja dans pubspec.yaml
- `dart:ffi` (memoire native) — inclus dans le SDK Dart
- `dart:isolate` (isolation crypto) — inclus dans le SDK Dart

---

## Fichiers de Code Generes

### Arborescence complete

```
Defensive_Report/code/
├── blindage_code/                          (P3 — Runtime Dart)
│   ├── fix_001_secure_memory.dart          SecureBytes, constantTimeEquals
│   ├── fix_002_secure_error_handling.dart   SecureErrorHandler, runZonedGuarded
│   ├── fix_003_crypto_isolate.dart          CryptoIsolate, PBKDF2 isole
│   ├── fix_004_sensitive_types.dart         PinBytes, SaltData, DerivedHash
│   ├── fix_005_sealed_security_states.dart  LockSecurityState sealed
│   ├── fix_006_secure_streams.dart          SecureStreamReader
│   ├── fix_007_nonce_manager.dart           NonceManager, SecureRandom
│   ├── test_fix_001.dart
│   ├── test_fix_002.dart
│   ├── test_fix_003.dart
│   ├── test_fix_004.dart
│   ├── test_fix_005.dart
│   ├── test_fix_006.dart
│   └── test_fix_007.dart
│
├── blindage_framework/                     (P4 — Framework/OS/AR)
│   ├── fix_008_009_navigation_confirmation.dart   RouteGuards, ProgressiveConfirmation
│   ├── fix_008_011_startup_security.dart           StartupSecurityChecker
│   ├── fix_012_035_ipc_auth.dart                   AuthenticatedIPC, DaemonIntegrity
│   ├── fix_013_screenshot_protection.dart          SensitiveDataField, ScreenCapture
│   ├── fix_015_016_os_sandbox.dart                 AppArmor, macOS entitlements
│   ├── fix_017_firewall_ssh_tailscale.dart         TailscaleFirewallRules
│   ├── fix_018_019_packaging_signing.dart          MSIX, Snap, DMG signature
│   ├── fix_020_security_audit_log.dart             SecurityAuditLog
│   ├── fix_021_022_obfuscation.dart                ConfidentialString
│   ├── fix_025_canary_values.dart                  CanaryManager
│   ├── fix_026_wdac_policy.dart                    WdacPolicy
│   ├── test_fix_008_009.dart
│   ├── test_fix_010_011.dart
│   ├── test_fix_012_014.dart
│   ├── test_fix_013.dart
│   ├── test_fix_015_016.dart
│   ├── test_fix_020.dart
│   └── test_fix_021_022.dart
│
├── blindage_reseau_crypto/                 (P5 — Reseau/Crypto)
│   ├── fix_027_secure_storage.dart         SecureStorageBackend multi-OS
│   ├── fix_028_030_native_memory.dart      NativeSecret (FFI, mlock)
│   ├── fix_029_key_rotation.dart           SshKeyRotation
│   ├── fix_031_040_post_quantum.dart       PostQuantumChecker
│   ├── fix_032_fail_closed.dart            FailClosedGuard, circuit breaker
│   ├── fix_033_dartssh2_config.dart        SshHardenedAlgorithms
│   ├── fix_034_secure_heartbeat.dart       SecureHeartbeat challenge-response
│   ├── fix_035_ipc_encryption.dart         IpcEncryption Encrypt-then-MAC
│   ├── fix_036_sshd_config.dart            SshdHardening
│   ├── fix_037_proxy_detection.dart        ProxyDetector
│   ├── fix_038_039_tailscale_state.dart    TailscaleSecurity, StateVerifier
│   ├── test_fix_027.dart
│   ├── test_fix_028_030.dart
│   ├── test_fix_032.dart
│   ├── test_fix_033.dart
│   ├── test_fix_034.dart
│   ├── test_fix_037.dart
│   └── test_fix_038_039.dart
│
└── pieges_decouragement/                   (P6 — Deception/BH)
    ├── fix_041_honeypot_ssh.dart            SshHoneypot
    ├── fix_042_canary_tokens.dart           CanaryTokenManager
    ├── fix_043_tarpit.dart                  SecurityTarpit
    ├── fix_044_secure_logging.dart          SecureLogger hash chain
    ├── fix_045_055_kill_switch.dart         KillSwitch + KillSwitchWatchdog
    ├── fix_046_duress_pin.dart              DuressPin
    ├── fix_047_048_moving_target_fingerprint.dart  MovingTarget + Fingerprinter
    ├── fix_049_050_botnet_tailscale_monitoring.dart  BotnetTailscaleMonitor
    ├── fix_051_mutual_attestation.dart      MutualAttestation
    ├── fix_052_053_ai_detection.dart        AIRateLimiter + BehavioralAnalyzer
    ├── fix_054_network_segmentation.dart    NetworkSegmentation
    ├── fix_056_supply_chain.dart            SupplyChainDefense
    ├── fix_057_058_forensics_cra.dart       ForensicsCollector + CraCompliance
    ├── test_fix_041.dart
    ├── test_fix_043.dart
    ├── test_fix_044.dart
    ├── test_fix_045_055.dart
    ├── test_fix_046.dart
    ├── test_fix_047_048.dart
    ├── test_fix_052_053.dart
    └── test_fix_054_056.dart
```

**Total** : 42 fichiers source + 29 fichiers test = **71 fichiers**, ~9 941 lignes

---

## Instructions par Fix

### Structure cible dans le projet

Chaque fichier de code doit etre copie dans `lib/core/security/` :

```
lib/core/security/
├── secure_memory.dart              ← FIX-001
├── secure_error_handler.dart       ← FIX-002
├── crypto_isolate.dart             ← FIX-003
├── sensitive_types.dart            ← FIX-004
├── security_states.dart            ← FIX-005
├── secure_streams.dart             ← FIX-006
├── nonce_manager.dart              ← FIX-007
├── navigation_confirmation.dart    ← FIX-008/009
├── startup_security.dart           ← FIX-010/011/014/023
├── ipc_auth.dart                   ← FIX-012/024
├── screenshot_protection.dart      ← FIX-013
├── sandbox_deployer.dart           ← FIX-015/016
├── tailscale_firewall.dart         ← FIX-017
├── code_signature.dart             ← FIX-018/019
├── security_audit_log.dart         ← FIX-020
├── confidential_string.dart        ← FIX-021/022
├── canary_values.dart              ← FIX-025
├── wdac_policy.dart                ← FIX-026
├── secure_storage.dart             ← FIX-027
├── native_secret.dart              ← FIX-028/030
├── ssh_key_rotation.dart           ← FIX-029
├── post_quantum_readiness.dart     ← FIX-031/040
├── fail_closed.dart                ← FIX-032
├── ssh_hardened_config.dart         ← FIX-033
├── secure_heartbeat.dart           ← FIX-034
├── ipc_encryption.dart             ← FIX-035
├── sshd_hardening.dart             ← FIX-036
├── proxy_detection.dart            ← FIX-037
├── tailscale_security.dart         ← FIX-038/039
├── honeypot_ssh.dart               ← FIX-041
├── canary_tokens.dart              ← FIX-042
├── tarpit.dart                     ← FIX-043
├── secure_logging.dart             ← FIX-044
├── kill_switch.dart                ← FIX-045/055
├── duress_pin.dart                 ← FIX-046
├── moving_target.dart              ← FIX-047/048
├── botnet_monitor.dart             ← FIX-049/050
├── mutual_attestation.dart         ← FIX-051
├── ai_detection.dart               ← FIX-052/053
├── network_segmentation.dart       ← FIX-054
├── supply_chain.dart               ← FIX-056
└── forensics_cra.dart              ← FIX-057/058
```

---

### Modifications dans les fichiers existants

#### 1. `lib/main.dart` (FIX-002)

```dart
// AVANT :
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(...));
}

// APRES :
import 'core/security/secure_error_handler.dart';
import 'core/security/startup_security.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SecureErrorHandler.initialize();

  // Verifications de securite au demarrage (FIX-010/011/014)
  await StartupSecurityChecker.runAllChecks();

  final prefs = await SharedPreferences.getInstance();
  SecureErrorHandler.runSecureApp(ProviderScope(...));
}
```

#### 2. `lib/features/lock/lock_provider.dart` (FIX-001, 003, 004, 027)

```dart
// AVANT :
String _hashPin(String pin, String salt) {
  final derived = _pbkdf2(pin, salt);
  return base64Encode(derived);
}

// APRES :
import '../../core/security/secure_memory.dart';
import '../../core/security/crypto_isolate.dart';
import '../../core/security/secure_storage.dart';

Future<String> _hashPin(String pin, String salt) async {
  final pinBytes = SecureBytes.fromString(pin);
  try {
    return await CryptoIsolate.hashPinIsolated(pin, salt);
  } finally {
    pinBytes.secureDispose();
  }
}

// Remplacer SharedPreferences par SecureStorage pour le hash PIN et le sel
final storage = await SecureStorage.getInstance();
await storage.write('pin_hash', hashValue);
```

#### 3. `lib/config/router.dart` (FIX-008)

```dart
// APRES :
import '../core/security/navigation_confirmation.dart';

final securityObserver = SecurityRouteObserver(
  onSensitivityChange: (sensitivity, route) { /* protection ecran */ },
);
final router = GoRouter(routes: [...], observers: [securityObserver]);
```

#### 4. `lib/features/security/` (FIX-009)

```dart
// AVANT :
onPressed: () => SecurityCommands.disableLinuxFirewall()

// APRES :
onPressed: () async {
  final result = await ProgressiveConfirmation.show(
    context: context,
    actionName: 'Desactiver le pare-feu',
    impactDescription: 'Votre PC sera expose...',
    dangerLevel: DangerLevel.high,
  );
  if (result == ConfirmationResult.confirmed) {
    await SecurityCommands.disableLinuxFirewall();
  }
}
```

#### 5. Scripts de build (FIX-021)

```bash
# Ajouter a tous les builds release :
flutter build linux --obfuscate --split-debug-info=build/debug-info
flutter build windows --obfuscate --split-debug-info=build/debug-info
flutter build macos --obfuscate --split-debug-info=build/debug-info
```

---

### Ordre d'integration recommande

```
Phase 1 — Fondations (P0, jour 1-2)
  FIX-001 → FIX-027 → FIX-012/014 → FIX-035 → FIX-032 → FIX-033

Phase 2 — Protection active (P1, jours 3-7)
  FIX-002 → FIX-010/011 → FIX-017 → FIX-020 → FIX-021/022
  FIX-034 → FIX-036 → FIX-042/043/044

Phase 3 — Defense avancee (P1 suite + P2, jours 8-30)
  FIX-045/052/055 → FIX-050/053/054
  FIX-003/004/007 → FIX-008/009/013
  FIX-015/016 → FIX-029/030 → FIX-037/038/039

Phase 4 — Backlog (P3, sprint suivant)
  FIX-005/006 → FIX-023/024/026
  FIX-031/040 → FIX-047/048 → FIX-057/058
```

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
