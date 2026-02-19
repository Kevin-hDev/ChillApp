# Inventaire des Failles — ChillApp

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Total** : **19 vulnerabilites** (3 critiques, 7 hautes, 5 moyennes, 3 basses, 1 info)

---

## Vue d'Ensemble

| Severite | Nombre | Pourcentage |
|----------|--------|-------------|
| CRITIQUE | 3 | 15.8% |
| HAUTE | 7 | 36.8% |
| MOYENNE | 5 | 26.3% |
| BASSE | 3 | 15.8% |
| INFO | 1 | 5.3% |

### Repartition par Categorie

| Categorie | Nombre | Failles |
|-----------|--------|---------|
| FLT (Flutter/Dart) | 6 | VULN-003, 004, 005, 012, 013, 015 |
| STO (Stockage) | 3 | VULN-002, 006, 010 |
| NET (Reseau) | 3 | VULN-009, 011, 014 |
| CRY (Crypto) | 3 | VULN-008, 017, 019 |
| SUP (Supply chain) | 1 | VULN-001 |
| NET (WoL) | 1 | VULN-018 |
| FLT (Anti-debug) | 1 | VULN-016 |

---

## Failles Critiques

### VULN-001 — Binaire daemon Tailscale sans verification d'integrite

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE |
| **CVSS** | 9.3 |
| **CWE** | CWE-494 (Download of Code Without Integrity Check) |
| **Categorie** | SUP (Supply chain) |

**Description** : Le daemon Go `chill-tailscale` (~33Mo par plateforme) est charge et execute sans aucune verification de checksum, signature ou hash. Un attaquant qui remplace le binaire obtient une execution de code au demarrage de l'app, avec forwarding SSH et acces au reseau Tailscale.

**Preuve dans le code** :
- **Fichier** : `lib/features/tailscale/tailscale_provider.dart`
- **Ligne** : 141
- **Code** : `_daemon = await Process.start(daemonPath, []);`
- **Probleme** : `Process.start()` execute le binaire sans verifier son integrite. `_getDaemonPath()` cherche dans plusieurs repertoires (lignes 92-129) mais ne verifie jamais un hash ou une signature.

**Exploitabilite** :
- Acces requis : local
- Complexite : basse
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur

**Flux concernes** : DF-003, DF-009 | **Secrets concernes** : SEC-006

---

### VULN-002 — Contournement du lock PIN par suppression des SharedPreferences

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE |
| **CVSS** | 8.1 |
| **CWE** | CWE-312 (Cleartext Storage of Sensitive Information) |
| **Categorie** | STO (Stockage) |

**Description** : Le hash PIN, le sel, le compteur d'echecs et le timestamp de verrouillage sont stockes dans SharedPreferences (fichier texte clair sur disque). Un attaquant avec acces au filesystem peut supprimer les cles `pin_hash` et `pin_salt` pour desactiver completement le verrou, ou modifier `pin_failed_attempts` et `pin_locked_until` pour reset le rate limiting.

**Preuve dans le code** :
- **Fichier** : `lib/features/lock/lock_provider.dart`
- **Ligne** : 65
- **Code** : `final hasPin = prefs.getString(_pinHashKey) != null;`
- **Probleme** : L'etat `isEnabled` depend uniquement de la presence de la cle dans SharedPreferences. Supprimer la cle = lock desactive. Le fichier SharedPreferences est un fichier texte lisible par tout processus du meme utilisateur.

**Exploitabilite** :
- Acces requis : local
- Complexite : basse
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur

**Flux concernes** : DF-001, DF-002 | **Secrets concernes** : SEC-002

---

### VULN-003 — Module securite peut desactiver toutes les protections OS

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE |
| **CVSS** | 8.5 |
| **CWE** | CWE-269 (Improper Privilege Management) |
| **Categorie** | FLT (Flutter/Desktop) |

**Description** : Les toggles de securite permettent de desactiver le pare-feu, activer SMBv1, activer RDP, desactiver AppArmor, desactiver fail2ban et desactiver les mises a jour automatiques. Un attaquant avec acces a l'interface (ou qui contourne le PIN via VULN-002) peut degrader systematiquement toute la securite du systeme en quelques clics.

**Preuve dans le code** :
- **Fichier** : `lib/features/security/security_commands.dart`
- **Ligne** : 30
- **Code** : `static Future<bool> disableWindowsFirewall() async { ... }`
- **Probleme** : Les methodes `disable*` existent pour chaque protection : `disableWindowsFirewall()`, `disableWindowsSmb1Protection()` (reactive SMBv1), `disableWindowsRdpProtection()` (active RDP), `disableLinuxFirewall()`, `disableLinuxAppArmor()`, `disableLinuxFail2ban()`. Pas de confirmation de securite supplementaire ni de journal d'audit.

**Exploitabilite** :
- Acces requis : local
- Complexite : basse
- Interaction utilisateur : requise (approbation pkexec/UAC)
- Privileges requis : acces a l'interface + mot de passe admin

**Flux concernes** : DF-006

---

## Failles Hautes

### VULN-004 — TOCTOU sur scripts temporaires executes en root

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 7.0 |
| **CWE** | CWE-367 (Time-of-check Time-of-use Race Condition) |
| **Categorie** | FLT (Flutter/Desktop) |

**Description** : Le pattern "ecrire un script dans /tmp puis l'executer via pkexec" cree une fenetre TOCTOU. Un attaquant avec des privileges eleves ou un acces au meme repertoire temporaire peut modifier le script entre l'ecriture et l'execution pkexec.

**Preuve dans le code** :
- **Fichier** : `lib/features/ssh_setup/ssh_setup_provider.dart`
- **Ligne** : 287
- **Code** :
```dart
await tempScript.writeAsString(script);
// ...
result = await CommandRunner.runElevated('bash', [tempScript.path]);
```
- **Probleme** : Fenetre temporelle entre `writeAsString()` et `runElevated()`. Meme pattern dans `security_commands.dart:293-299` et `wol_setup_provider.dart:316-354`.

**Exploitabilite** :
- Acces requis : local
- Complexite : haute
- Interaction utilisateur : aucune
- Privileges requis : root (pour modifier des fichiers chmod 700)

**Flux concernes** : DF-005, DF-006, DF-007 | **Secrets concernes** : SEC-004

---

### VULN-005 — Fichier .desktop Linux - chemin executable non echappe

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 7.3 |
| **CWE** | CWE-78 (OS Command Injection) |
| **Categorie** | FLT (Flutter/Desktop) |

**Description** : Le chemin de l'executable est interpole directement dans le champ `Exec=` du fichier `.desktop` sans echappement. Si le chemin contient des caracteres speciaux, cela peut causer une injection de commande lors du lancement au demarrage.

**Preuve dans le code** :
- **Fichier** : `lib/features/settings/settings_provider.dart`
- **Ligne** : 98
- **Code** : `'Exec=$exePath\n'`
- **Probleme** : `Platform.resolvedExecutable` est insere directement dans le fichier `.desktop`. La spec Desktop Entry requiert un echappement specifique pour les arguments Exec.

**Exploitabilite** :
- Acces requis : local
- Complexite : moyenne
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur (ecriture dans `~/.config/autostart/`)

**Flux concernes** : DF-010

---

### VULN-006 — Cles Tailscale stockees sans chiffrement au repos

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 7.5 |
| **CWE** | CWE-312 (Cleartext Storage of Sensitive Information) |
| **Categorie** | STO (Stockage) |

**Description** : Les cles WireGuard du noeud Tailscale sont stockees dans `~/.local/share/chill-app/tailscale/` avec uniquement des permissions fichier (0700). Tout processus du meme utilisateur peut lire ces cles et usurper l'identite du noeud Tailscale.

**Preuve dans le code** :
- **Fichier** : `tailscale-daemon/main.go`
- **Ligne** : 69
- **Code** : `os.MkdirAll(dir, 0700)`
- **Probleme** : Permissions 0700 ne protegent que contre les AUTRES utilisateurs. Tout processus du meme utilisateur (malware, extension navigateur, autre app) peut lire les cles. Pas de chiffrement au repos.

**Exploitabilite** :
- Acces requis : local
- Complexite : basse
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur

**Flux concernes** : DF-012 | **Secrets concernes** : SEC-003

---

### VULN-007 — IPC daemon Go sans authentification

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 7.1 |
| **CWE** | CWE-419 (Unprotected Primary Channel) |
| **Categorie** | FLT (Flutter/Desktop) |

**Description** : La communication entre l'app Flutter et le daemon Go se fait par JSON en clair sur stdin/stdout. Il n'y a pas d'authentification — si un processus peut ecrire sur le stdin du daemon, il peut envoyer des commandes (login, logout, shutdown, status).

**Preuve dans le code** :
- **Fichier** : `lib/features/tailscale/tailscale_provider.dart`
- **Ligne** : 294
- **Code** : `_daemon!.stdin.writeln(jsonEncode(cmd));`
- **Probleme** : Les commandes sont envoyees en JSON clair. Le daemon Go accepte toute commande valide sur stdin sans verifier l'identite de l'emetteur. Cote daemon : `main.go:240-262` parse et execute sans authentification.

**Exploitabilite** :
- Acces requis : local
- Complexite : moyenne
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur (acces au processus)

**Flux concernes** : DF-003

---

### VULN-008 — PIN en memoire Dart non effacable (strings immutables)

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 6.8 |
| **CWE** | CWE-316 (Cleartext Storage of Sensitive Information in Memory) |
| **Categorie** | CRY (Crypto) |

**Description** : Les strings Dart sont immutables et gerees par le garbage collector. Le PIN en clair reste en memoire apres le calcul PBKDF2 et ne peut pas etre efface de maniere fiable.

**Preuve dans le code** :
- **Fichier** : `lib/features/lock/lock_provider.dart`
- **Ligne** : 143
- **Code** : `Future<void> setPin(String pin) async {`
- **Probleme** : Le parametre `pin` est un String Dart immutable. Apres `setPin()` ou `verifyPin()`, le GC peut ou non liberer la memoire. Documente comme SE-PIN-011 dans le code (ligne 14-18).

**Exploitabilite** :
- Acces requis : local
- Complexite : moyenne
- Interaction utilisateur : aucune
- Privileges requis : root (pour dump memoire)

**Flux concernes** : DF-001, DF-002 | **Secrets concernes** : SEC-001

---

### VULN-009 — SSH forwarding Tailscale sans filtrage additionnel

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 7.5 |
| **CWE** | CWE-284 (Improper Access Control) |
| **Categorie** | NET (Reseau) |

**Description** : Le daemon Go forwarde TOUTES les connexions sur le port 22 Tailscale vers `localhost:22` sans filtrage additionnel. Tout appareil autorise sur le tailnet peut se connecter au SSH de la machine. Si un autre noeud Tailscale est compromis, il obtient un acces SSH direct.

**Preuve dans le code** :
- **Fichier** : `tailscale-daemon/main.go`
- **Ligne** : 181
- **Code** : `localConn, err := net.DialTimeout("tcp", "127.0.0.1:22", 5*time.Second)`
- **Probleme** : `startForwarding()` (ligne 147-177) accepte toute connexion entrante sur le port 22 sans whitelist d'IP, sans limitation de debit, sans journal des connexions. Le seul controle est l'appartenance au tailnet.

**Exploitabilite** :
- Acces requis : reseau (tailscale mesh)
- Complexite : basse
- Interaction utilisateur : aucune
- Privileges requis : noeud tailscale autorise

**Flux concernes** : DF-009

---

### VULN-010 — Rate limiting PIN cote client uniquement

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE |
| **CVSS** | 6.5 |
| **CWE** | CWE-307 (Improper Restriction of Excessive Authentication Attempts) |
| **Categorie** | STO (Stockage) |

**Description** : Le rate limiting du PIN (backoff exponentiel apres 5 echecs) est stocke dans SharedPreferences. Un attaquant peut modifier `pin_failed_attempts` (remettre a 0) et supprimer `pin_locked_until` pour reset le rate limiting et continuer le brute force.

**Preuve dans le code** :
- **Fichier** : `lib/features/lock/lock_provider.dart`
- **Ligne** : 215
- **Code** : `await prefs.setInt(_lockedUntilKey, newLockedUntil.millisecondsSinceEpoch);`
- **Probleme** : Le compteur d'echecs et le timestamp de verrouillage sont dans SharedPreferences — un fichier texte modifiable par tout processus du meme utilisateur. Reset du compteur = brute force illimite sur 10^8 combinaisons (8 chiffres).

**Exploitabilite** :
- Acces requis : local
- Complexite : basse
- Interaction utilisateur : aucune
- Privileges requis : meme utilisateur

**Flux concernes** : DF-002 | **Secrets concernes** : SEC-002

---

## Failles Moyennes

### VULN-011 — Info reseau sensible dans presse-papiers

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE |
| **CVSS** | 4.3 |
| **CWE** | CWE-200 (Exposure of Sensitive Information) |

**Description** : Les informations reseau (IP, MAC, hostname) sont affichees et copiables dans le presse-papiers, lisible par toutes les applications.

**Preuve** : `lib/shared/widgets/copyable_info.dart:1` — Widget `CopyableInfo` permet la copie sans effacement automatique.

---

### VULN-012 — Processus orphelins apres timeout

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE |
| **CVSS** | 5.3 |
| **CWE** | CWE-404 (Improper Resource Shutdown or Release) |

**Description** : `Process.run().timeout()` ne tue pas le processus sous-jacent. Les processus pkexec continuent en arriere-plan apres timeout, avec potentielle accumulation.

**Preuve** : `lib/core/command_runner.dart:27` — Commentaire documentant la limitation.

---

### VULN-013 — Pas d'obfuscation du binaire Flutter desktop

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE |
| **CVSS** | 4.0 |
| **CWE** | CWE-693 (Protection Mechanism Failure) |

**Description** : L'application n'est pas compilee avec `--obfuscate --split-debug-info`. Le binaire contient les noms de classes, methodes et variables en clair.

**Preuve** : `pubspec.yaml:1` — Pas de configuration d'obfuscation. Le reverse engineering est trivial avec Blutter + GhidrAssist.

---

### VULN-014 — google_fonts telecharge au runtime sans pinning

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE |
| **CVSS** | 4.8 |
| **CWE** | CWE-295 (Improper Certificate Validation) |

**Description** : Le package `google_fonts` telecharge les polices depuis `fonts.googleapis.com` au runtime. Sans certificate pinning, un MITM pourrait servir des polices malformees (ref: CVE-2025-27363 FreeType).

**Preuve** : `pubspec.yaml:16` — `google_fonts: ^8.0.1` sans certificate pinning.

---

### VULN-015 — plist macOS - chemin executable non echappe dans XML

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE |
| **CVSS** | 5.5 |
| **CWE** | CWE-78 (OS Command Injection) |

**Description** : Le chemin de l'executable est insere directement dans le plist XML sans echappement des caracteres speciaux XML (`<`, `>`, `&`, `"`).

**Preuve** : `lib/features/settings/settings_provider.dart:116` — `'    <string>$exePath</string>\n'` — Interpolation directe sans echappement XML.

---

## Failles Basses

### VULN-016 — Pas de protection anti-debug/Frida sur desktop

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE |
| **CVSS** | 3.1 |
| **CWE** | CWE-489 (Active Debug Code) |

**Description** : L'application ne detecte pas les debuggers (gdb, lldb) ni les outils d'instrumentation (Frida). Un attaquant peut instrumenter l'app pour contourner le PIN.

**Preuve** : `lib/main.dart:1` — Aucune detection de debugger ou d'instrumentation dynamique.

---

### VULN-017 — Migration legacy SHA-256 simple vers PBKDF2

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE |
| **CVSS** | 3.7 |
| **CWE** | CWE-916 (Use of Password Hash With Insufficient Computational Effort) |

**Description** : Le code supporte encore la migration depuis l'ancien format SHA-256 simple (sans sel). Un PIN au format legacy est vulnerable au brute force instantane (rainbow tables).

**Preuve** : `lib/features/lock/lock_provider.dart:186` — `final oldHash = sha256.convert(utf8.encode(pin)).toString();` — SHA-256 sans sel.

---

### VULN-018 — WoL magic packet sans authentification

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE |
| **CVSS** | 3.1 |
| **CWE** | CWE-306 (Missing Authentication for Critical Function) |

**Description** : Les paquets WoL sont des broadcasts non authentifies. N'importe qui sur le LAN peut reveiller la machine. L'adresse MAC est affichee dans l'interface.

**Preuve** : `lib/features/wol_setup/wol_setup_provider.dart:228` — MAC affichee et copiable.

---

## Info

### VULN-019 — Pas de plan de migration post-quantique

| Champ | Valeur |
|-------|--------|
| **Severite** | INFO |
| **CVSS** | 0.0 |
| **CWE** | CWE-327 (Use of a Broken or Risky Cryptographic Algorithm) |

**Description** : SSH et WireGuard/Tailscale utilisent des algorithmes classiques sans plan de migration vers ML-KEM/ML-DSA. Impact theorique a long terme (harvest-now-decrypt-later).

**Preuve** : `tailscale-daemon/main.go:158` — Pas de support des algorithmes post-quantiques.

---

## Couverture de l'Analyse

| Base de connaissances | Resultat |
|-----------------------|----------|
| ssh-attack-vectors.md | Scanne — pas de dartssh2 (app configure OpenSSH natif) |
| tailscale-attack-vectors.md | Scanne — VULN-001, 006, 007, 009 |
| flutter-dart-attacks.md | Scanne — VULN-003, 004, 005, 007, 008, 012, 013, 015, 016 |
| crypto-weaknesses.md | Scanne — VULN-008, 017, 019 |
| storage-key-attacks.md | Scanne — VULN-002, 006, 010 |
| network-attacks.md | Scanne — VULN-009, 011, 014, 018 |
| desktop-specific-attacks.md | Scanne — VULN-004, 005, 012, 015, 016 |
| mobile-specific-attacks.md | Non applicable (app desktop uniquement) |
| ai-offensive-threats.md | Scanne — VULN-013 (RE par IA) |
| cve-reference.md | Scanne — pas de CVE directement applicable |

---

**Rapport genere par** : Adversary Simulation v1.0.0
**Session** : CHILLAPP_20260218_140000
