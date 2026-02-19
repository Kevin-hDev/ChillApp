# P4 — Blindage Framework Flutter + OS + Anti-Reverse

**Projet** : ChillApp
**Date** : 18 fevrier 2026
**Entree** : P2_reinforcement_points.yaml (19 gaps assignes a P4)
**Knowledge** : flutter-framework-hardening.md (19), os-hardening.md (11), anti-reverse-engineering.md (12)

---

## Synthese

**19 gaps traites. 10 fichiers de code ecrits. 7 fichiers de test ecrits.**

Chaque fix est un fichier Dart complet et integrable. Les fixes sont regroupes logiquement :

| Groupe | Fichier | Gaps couverts |
|--------|---------|---------------|
| Demarrage securise | fix_008_011_startup_security.dart | GAP-010, 011, 014, 023 |
| IPC authentifie | fix_012_035_ipc_auth.dart | GAP-012, 024 |
| Navigation + Confirmation | fix_008_009_navigation_confirmation.dart | GAP-008, 009 |
| Protection ecran | fix_013_screenshot_protection.dart | GAP-013 |
| Sandbox OS | fix_015_016_os_sandbox.dart | GAP-015, 016 |
| Firewall Tailscale | fix_017_firewall_ssh_tailscale.dart | GAP-017 |
| Packaging + Signature | fix_018_019_packaging_signing.dart | GAP-018, 019 |
| Journal d'audit | fix_020_security_audit_log.dart | GAP-020 |
| Obfuscation | fix_021_022_obfuscation.dart | GAP-021, 022 |
| Canary values | fix_025_canary_values.dart | GAP-025 |
| WDAC Windows | fix_026_wdac_policy.dart | GAP-026 |

---

## Detail des Protections

### FIX-008 : Route Guards (P2)

**Probleme** : Les pages SSH, Settings, Security ne declenchent aucune protection supplementaire.

**Solution** : `SecurityRouteObserver` + mapping `routeSensitivity` qui classifie chaque route en normal/sensitive/critical. Les pages critical activent automatiquement la protection d'ecran.

---

### FIX-009 : Confirmation Progressive (P2)

**Probleme** : Un seul clic desactive le pare-feu ou AppArmor. Risque d'erreur et d'exploitation.

**Solution** : `ProgressiveConfirmation` en 3 etapes :
1. Avertissement avec detail de l'impact
2. Delai obligatoire (3s medium, 5s high)
3. Saisie "CONFIRMER" (high seulement)

---

### FIX-010/011 : Startup Security Checker (P1)

**Probleme** : Aucune verification au demarrage. DLL hijacking, LD_PRELOAD, debugger, Frida non detectes.

**Solution** : `StartupSecurityChecker.runAllChecks()` qui combine :
- Verification LD_PRELOAD (Linux) / DYLD_INSERT_LIBRARIES (macOS)
- Detection debugger (TracerPid, sysctl, PowerShell)
- Scan ports Frida (27042-27044)
- En release : exit(1) si menace critique

---

### FIX-012/024 : IPC Authentifie + Integrite Daemon (P0)

**Probleme** : Le daemon Go est execute sans verification. L'IPC est du JSON clair sans authentification.

**Solution** :
- `DaemonIntegrityVerifier` : SHA-256 du binaire verifie avant execution
- `AuthenticatedIPC` : HMAC-SHA256 sur chaque message + nonce anti-replay + timestamp 30s
- Comparaison en temps constant

---

### FIX-013 : Protection Capture Ecran (P2)

**Probleme** : Un malware peut capturer l'ecran et lire les secrets.

**Solution** :
- `SensitiveDataField` : masque les donnees par defaut, revele 10s max
- `ScreenCaptureDetector` : scan periodique des processus de capture
- `ScreenCaptureWarning` : banniere d'avertissement

---

### FIX-015/016 : Sandbox OS (P2)

**Probleme** : L'app tourne sans restriction sur Linux et macOS.

**Solution** :
- **Linux** : Profil AppArmor restrictif (reseau, fichiers, deny ptrace/sudo)
- **macOS** : Entitlements restrictifs (pas de camera, micro, contacts, JIT)

---

### FIX-017 : Firewall SSH Tailscale (P1)

**Probleme** : SSH ouvert a toutes les IPs au lieu de Tailscale uniquement.

**Solution** : `TailscaleFirewallRules` multi-OS :
- Linux : nftables ou UFW fallback
- macOS : pf anchor
- Windows : New-NetFirewallRule

Autorise SSH uniquement depuis 100.64.0.0/10.

---

### FIX-018/019 : Packaging + Signature (P1-P2)

**Probleme** : Aucune signature, aucun sandbox packaging.

**Solution** :
- Windows : MSIX signe (Authenticode)
- Linux : Snap avec confinement strict + GPG
- macOS : DMG notarise (Developer ID)
- Verification runtime : `CodeSignatureVerifier.verifyCurrentBinary()`

---

### FIX-020 : Journal d'Audit Securise (P1)

**Probleme** : Aucune trace quand quelqu'un desactive les protections.

**Solution** : `SecurityAuditLog` avec :
- Chaine de hachage HMAC (anti-tamper)
- Sanitisation automatique (pas de secrets dans les logs)
- Rotation a 10000 entrees
- Verification d'integrite

---

### FIX-021/022 : Obfuscation (P1)

**Probleme** : Noms de classes en clair + chaines lisibles dans le binaire.

**Solution** :
- `--obfuscate --split-debug-info` sur tous les builds release
- `ConfidentialString` : chiffrement XOR derive des litteraux sensibles
- `StrongConfidential` : PRNG derive par ID unique

---

### FIX-025 : Canary Values (P2)

**Probleme** : Aucune detection de tampering memoire/fichiers/config.

**Solution** : `CanaryManager` avec 3 types :
- `MemoryCanary` : valeur sentinelle SHA-256 en memoire
- `FileCanary` : faux fichier de credentials (detecte acces)
- `ConfigCanary` : checksums des fichiers de configuration

---

### FIX-026 : WDAC Windows (P3)

**Probleme** : N'importe quel binaire peut s'executer dans le contexte de l'app.

**Solution** : Politique WDAC whitelistant uniquement les binaires signes de ChillApp.
Mode audit d'abord, enforce apres validation. Windows Pro/Enterprise uniquement.

---

## Structure de Fichiers a Creer

```
lib/core/security/
  startup_security.dart            <-- FIX-010/011/014/023
  ipc_auth.dart                    <-- FIX-012/024
  navigation_confirmation.dart     <-- FIX-008/009
  screenshot_protection.dart       <-- FIX-013
  sandbox_deployer.dart            <-- FIX-015/016
  tailscale_firewall.dart          <-- FIX-017
  code_signature.dart              <-- FIX-019
  security_audit_log.dart          <-- FIX-020
  confidential_string.dart         <-- FIX-022
  canary_values.dart               <-- FIX-025
  wdac_policy.dart                 <-- FIX-026

scripts/
  build_release.dart               <-- FIX-021
  build_windows.sh                 <-- FIX-018
  build_linux.sh                   <-- FIX-018
  build_macos.sh                   <-- FIX-018

snap/
  snapcraft.yaml                   <-- FIX-018
```

---

## Couverture Knowledge

| Knowledge | Sections | Traitees | NA | Differe |
|-----------|----------|----------|----|---------|
| flutter-framework-hardening.md | 19 | 10 | 6 | 3 |
| os-hardening.md | 11 | 7 | 4 | 0 |
| anti-reverse-engineering.md | 12 | 10 | 2 | 0 |
| **Total** | **42** | **27** | **12** | **3** |

**Score** : 27/42 sections couvertes (64%)

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
