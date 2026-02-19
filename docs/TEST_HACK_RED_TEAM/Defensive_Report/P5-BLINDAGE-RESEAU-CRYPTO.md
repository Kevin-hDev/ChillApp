# P5 — Blindage Reseau et Crypto

**Projet** : ChillApp
**Date** : 18 fevrier 2026
**Entree** : P2_reinforcement_points.yaml (14 gaps assignes a P5)
**Knowledge** : storage-crypto-hardening.md (8), network-hardening.md (15)

---

## Synthese

**14 gaps traites. 11 fichiers de code ecrits. 7 fichiers de test ecrits.**

Chaque fix est un fichier Dart complet et integrable. Les fixes sont regroupes logiquement :

| Groupe | Fichier | Gaps couverts |
|--------|---------|---------------|
| Stockage securise multi-OS | fix_027_secure_storage.dart | GAP-027 |
| Memoire native FFI + cold boot | fix_028_030_native_memory.dart | GAP-028, 030 |
| Rotation cles SSH | fix_029_key_rotation.dart | GAP-029 |
| Fail closed | fix_032_fail_closed.dart | GAP-032 |
| dartssh2 durci | fix_033_dartssh2_config.dart | GAP-033 |
| Heartbeat securise | fix_034_secure_heartbeat.dart | GAP-034 |
| Chiffrement IPC | fix_035_ipc_encryption.dart | GAP-035 |
| sshd_config durci | fix_036_sshd_config.dart | GAP-036 |
| Detection proxy/VPN | fix_037_proxy_detection.dart | GAP-037 |
| Tailscale securite + etat signe | fix_038_039_tailscale_state.dart | GAP-038, 039 |
| Post-quantique (documentation) | fix_031_040_post_quantum.dart | GAP-031, 040 |

---

## Detail des Protections

### FIX-027 : Migration Stockage Securise (P0)

**Probleme** : SharedPreferences stocke le hash PIN, le sel et les preferences en JSON clair lisible par tout processus. La suppression du fichier desactive le lock.

**Solution** : `SecureStorageBackend` avec 4 implementations :
- **Linux** : `LinuxSecureStorage` via secret-tool (libsecret / GNOME Keyring)
- **Windows** : `WindowsSecureStorage` via PowerShell Export-Clixml (DPAPI)
- **macOS** : `MacOSSecureStorage` via security add-generic-password (Keychain)
- **Fallback** : `FallbackSecureStorage` avec chiffrement XOR derive du machine-id

Factory `SecureStorage.getInstance()` detecte automatiquement l'OS.

---

### FIX-028/030 : Memoire Native FFI + Cold Boot (P1/P2)

**Probleme** : Le GC Dart copie les secrets en memoire. Les copies persistent apres extinction (remanence DRAM).

**Solution** : `NativeSecret` utilisant dart:ffi :
- `calloc()` via libc (Linux/macOS) ou HeapAlloc (Windows) — hors GC Dart
- `mlock()` pour verrouiller en memoire (pas de swap sur disque)
- Triple-pass zero (0 → 0xFF → 0) a la liberation
- `dispose()` obligatoire avec `try/finally`

---

### FIX-029 : Rotation Automatique des Cles SSH (P2)

**Probleme** : Les cles SSH sont statiques. En cas de compromission, l'acces reste ouvert indefiniment.

**Solution** : `SshKeyRotation` :
- Verification de l'age au demarrage (30 jours par defaut)
- Generation ed25519 avec ssh-keygen
- Deploiement automatique de la cle publique via SSH
- Revocation de l'ancienne cle dans authorized_keys
- Nettoyage des backups > 90 jours

---

### FIX-032 : Politique Fail Closed (P0)

**Probleme** : Si le daemon plante ou Tailscale est down, l'app pourrait tenter un fallback non securise (CWE-636).

**Solution** : `FailClosedGuard` avec circuit breaker :
- 3 verifications avant chaque connexion : Tailscale actif, daemon actif, IP valide
- `validateDestination()` : UNIQUEMENT IPs Tailscale (100.64.0.0/10 ou fd7a:115c:a1e0::/48) et hostnames .ts.net
- Circuit breaker : 3 echecs consecutifs = blocage total pendant 5 minutes
- `executeSecure()` wrapper qui combine toutes les verifications
- `forceOpen()` pour urgences

---

### FIX-033 : Configuration dartssh2 Durcie (P0)

**Probleme** : dartssh2 utilise des algorithmes par defaut incluant DH group1-sha1, RSA 1024, et CBC (Terrapin CVE-2023-48795).

**Solution** : `SshHardenedAlgorithms` avec whitelist/blacklist :
- **KEX** : curve25519-sha256, ecdh-sha2-nistp{256,384,521}, DH group16/18-sha512
- **Host Keys** : ssh-ed25519, ecdsa-sha2-nistp{256,384,521}, rsa-sha2-{256,512}
- **Ciphers** : aes256-gcm, aes128-gcm, chacha20-poly1305, aes{128,192,256}-ctr
- **MACs** : hmac-sha2-{256,512}-etm, hmac-sha2-{256,512}
- **Blacklist** : 19 algorithmes dangereux (SHA-1, CBC, MD5, arcfour, 3DES)

`SshConfigValidator.validateServer()` verifie qu'au moins un algorithme securise est disponible dans chaque categorie.

---

### FIX-034 : Heartbeat Securise Challenge-Response (P1)

**Probleme** : Aucun heartbeat entre l'app et le daemon. Impossible de detecter un crash, une compromission ou un MITM.

**Solution** : `SecureHeartbeat` :
- Challenge aleatoire 32 bytes (CSPRNG) toutes les 15 secondes
- Le daemon repond HMAC-SHA256(challenge, sharedKey)
- Comparaison en temps constant
- Timeout strict 5 secondes
- 3 echecs = etat `dead` → FailClosedGuard.forceOpen()
- Latence moyenne calculee sur les 10 derniers succes

---

### FIX-035 : Chiffrement IPC Encrypt-then-MAC (P0)

**Probleme** : Les messages IPC entre l'app et le daemon sont du JSON brut sur stdin/stdout.

**Solution** : `IpcEncryption` :
- Echange de cle CSPRNG au demarrage (contributions 32 bytes de chaque cote)
- Derivation HKDF-like : cle de chiffrement + cle de MAC
- XOR keystream derive de SHA-256(key + nonce + counter)
- HMAC-SHA256 Encrypt-then-MAC sur nonce + ciphertext
- Nonce monotone (compteur 8 bytes + random 4 bytes) anti-replay
- Se combine avec FIX-012 (authentification HMAC)

---

### FIX-036 : Template sshd_config Durci (P1)

**Probleme** : Le PC cible peut avoir une config SSH faible (mots de passe, root login, algorithmes obsoletes).

**Solution** : `SshdHardening` :
- Template complet avec 30+ parametres durcis
- `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`
- KEX, ciphers et MACs alignes avec FIX-033
- `AllowUsers *@100.64.0.0/10` (Tailscale uniquement)
- `auditConfig()` verifie 15+ parametres avec severite (critical/warning/info)
- `deployHardenedConfig()` avec backup et test (sshd -t) avant activation

---

### FIX-037 : Detection Proxy/VPN Tiers (P2)

**Probleme** : Un proxy MITM (Burp Suite, mitmproxy, Charles) ou un VPN non-Tailscale peut intercepter les communications.

**Solution** : `ProxyDetector` avec 4 vecteurs de detection :
1. **Variables d'environnement** : http_proxy, https_proxy, socks_proxy, etc.
2. **Ports proxy locaux** : 11 ports (8080, 8888, 9090, 3128, 1080...)
3. **Interfaces VPN** : tun, tap, wg, ppp, utun, nord, proton, mullvad (exclut Tailscale)
4. **Table de routage** : routes par defaut via interfaces VPN

Scan au demarrage et toutes les 5 minutes. Proxy critique = fail closed.

---

### FIX-038 : Fonctionnalites Tailscale 1.94.1 (P2)

**Probleme** : Le daemon Go n'exploite pas le TPM, les tokens OIDC ephemeres ni l'audit SSH de Tailscale.

**Solution** :
- `TailscaleSecurityConfig` : TPM, OIDC ephemere, SSH audit, MagicDNS
- `TailscaleSecurityChecker.audit()` : verifie version >= 1.94.0, etat, MagicDNS, SSH
- `checkTpmAvailable()` : /dev/tpmrm0 (Linux), Get-Tpm (Windows), Secure Enclave (macOS)

---

### FIX-039 : Synchronisation d'Etat Signee (P2)

**Probleme** : L'etat du daemon (connecte/deconnecte) est transmis en clair. Un attaquant peut forger des messages d'etat.

**Solution** : `StateVerifier` + `SignedState` :
- Chaque message d'etat signe avec HMAC-SHA256(state|timestamp|sequence)
- Verification du timestamp (drift max 30 secondes)
- Verification du numero de sequence (monotone strict, anti-replay)
- Comparaison HMAC en temps constant

---

### FIX-031/040 : Preparation Post-Quantique (P3)

**Probleme** : "Harvest now, decrypt later" — le trafic SSH actuel pourra etre dechiffre par un ordinateur quantique.

**Solution** : Documentation et verification :
- `PostQuantumChecker.assess()` : verifie OpenSSH version, dartssh2, WireGuard
- Strategie de migration en 4 phases :
  1. Immediat : curve25519-sha256 + aes256-gcm (FIX-033)
  2. OpenSSH >= 9.0 : sntrup761x25519-sha512 cote serveur
  3. dartssh2 + ML-KEM : mlkem768x25519-sha256 (FIPS 203)
  4. Full PQ : ML-DSA signatures + Rosenpass WireGuard

---

## Structure de Fichiers a Creer

```
lib/core/security/
  secure_storage.dart            <-- FIX-027
  native_secret.dart             <-- FIX-028/030
  ssh_key_rotation.dart          <-- FIX-029
  post_quantum_readiness.dart    <-- FIX-031/040
  fail_closed.dart               <-- FIX-032
  ssh_hardened_config.dart       <-- FIX-033
  secure_heartbeat.dart          <-- FIX-034
  ipc_encryption.dart            <-- FIX-035
  sshd_hardening.dart            <-- FIX-036
  proxy_detection.dart           <-- FIX-037
  tailscale_security.dart        <-- FIX-038/039
```

---

## Couverture Knowledge

| Knowledge | Sections | Traitees | NA | Differees |
|-----------|----------|----------|----|-----------|
| storage-crypto-hardening.md | 8 | 5 | 2 | 0 |
| network-hardening.md | 15 | 9 | 3 | 1 |
| **Total** | **23** | **14** | **5** | **1** |

**Score** : 14/23 sections couvertes (61%)

Note : 2 sections storage-crypto deja couvertes en P3 (PBKDF2, secure random).

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
