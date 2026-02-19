# P3 - Chasse aux Failles

## Synthese

19 vulnerabilites decouvertes : 3 CRITIQUES, 7 HAUTES, 5 MOYENNES, 3 BASSES, 1 INFO. Les failles les plus devastatrices sont l'absence de verification d'integrite du binaire daemon Tailscale (supply chain), le contournement du lock PIN par suppression de fichier, et la possibilite de desactiver toutes les protections OS via le module securite. L'application est une cible de choix car elle combine acces root, stockage en clair et IPC non authentifie.

## Tableau des Vulnerabilites

| ID | Titre | Severite | CVSS | CWE | Categorie |
|----|-------|----------|------|-----|-----------|
| VULN-001 | Binaire daemon Tailscale sans verification d'integrite | **CRITIQUE** | 9.3 | CWE-494 | SUP |
| VULN-002 | Contournement du lock PIN par suppression SharedPreferences | **CRITIQUE** | 8.1 | CWE-312 | STO |
| VULN-003 | Module securite peut desactiver toutes les protections OS | **CRITIQUE** | 8.5 | CWE-269 | FLT |
| VULN-004 | TOCTOU sur scripts temporaires executes en root | HAUTE | 7.0 | CWE-367 | FLT |
| VULN-005 | Fichier .desktop Linux - chemin executable non echappe | HAUTE | 7.3 | CWE-78 | FLT |
| VULN-006 | Cles Tailscale stockees sans chiffrement au repos | HAUTE | 7.5 | CWE-312 | STO |
| VULN-007 | IPC daemon Go sans authentification | HAUTE | 7.1 | CWE-419 | FLT |
| VULN-008 | PIN en memoire Dart non effacable (strings immutables) | HAUTE | 6.8 | CWE-316 | CRY |
| VULN-009 | SSH forwarding Tailscale sans filtrage additionnel | HAUTE | 7.5 | CWE-284 | NET |
| VULN-010 | Rate limiting PIN cote client uniquement | HAUTE | 6.5 | CWE-307 | STO |
| VULN-011 | Info reseau sensible dans presse-papiers | MOYENNE | 4.3 | CWE-200 | NET |
| VULN-012 | Processus orphelins apres timeout | MOYENNE | 5.3 | CWE-404 | FLT |
| VULN-013 | Pas d'obfuscation du binaire Flutter desktop | MOYENNE | 4.0 | CWE-693 | FLT |
| VULN-014 | google_fonts telecharge au runtime sans pinning | MOYENNE | 4.8 | CWE-295 | NET |
| VULN-015 | plist macOS - chemin executable non echappe dans XML | MOYENNE | 5.5 | CWE-78 | FLT |
| VULN-016 | Pas de protection anti-debug/Frida sur desktop | BASSE | 3.1 | CWE-489 | FLT |
| VULN-017 | Migration legacy SHA-256 simple vers PBKDF2 | BASSE | 3.7 | CWE-916 | CRY |
| VULN-018 | WoL magic packet sans authentification | BASSE | 3.1 | CWE-306 | NET |
| VULN-019 | Pas de plan de migration post-quantique | INFO | 0.0 | CWE-327 | CRY |

## Detail des Failles CRITIQUES

### VULN-001 — Binaire daemon Tailscale sans verification d'integrite (CVSS 9.3)

**CWE** : CWE-494 (Download of Code Without Integrity Check)
**Categorie** : Supply Chain (SUP)

**Ou dans le code** : `tailscale_provider.dart:141`
```dart
_daemon = await Process.start(daemonPath, []);
```

**Le probleme** : Le daemon Go chill-tailscale (~33Mo par plateforme) est charge et execute sans aucune verification de checksum, signature ou hash. La methode `_getDaemonPath()` (lignes 92-129) cherche le binaire dans plusieurs repertoires mais ne verifie jamais son integrite.

**Ce que le hacker obtient** : Remplacer le binaire = execution de code au demarrage de l'app. Le daemon a acces au reseau Tailscale, au forwarding SSH, et aux cles WireGuard. C'est la faille la plus grave du projet.

**Flux impactes** : DF-003 (IPC), DF-009 (SSH forwarding)
**Secrets exposes** : SEC-006 (binaire daemon)

---

### VULN-002 — Contournement du lock PIN par suppression SharedPreferences (CVSS 8.1)

**CWE** : CWE-312 (Cleartext Storage of Sensitive Information)
**Categorie** : Stockage (STO)

**Ou dans le code** : `lock_provider.dart:65`
```dart
final hasPin = prefs.getString(_pinHashKey) != null;
```

**Le probleme** : L'etat `isEnabled` du lock depend uniquement de la presence de la cle `pin_hash` dans SharedPreferences — un fichier texte clair sur disque. Un attaquant peut :
1. **Supprimer** les cles `pin_hash` et `pin_salt` → lock desactive
2. **Lire** le hash pour un brute force offline
3. **Modifier** `pin_failed_attempts` et `pin_locked_until` pour reset le rate limiting

**Flux impactes** : DF-001 (stockage PIN), DF-002 (verification)
**Secrets exposes** : SEC-002 (hash + sel PIN)

---

### VULN-003 — Module securite peut desactiver toutes les protections OS (CVSS 8.5)

**CWE** : CWE-269 (Improper Privilege Management)
**Categorie** : Flutter/Dart (FLT)

**Ou dans le code** : `security_commands.dart:30+`
```dart
static Future<bool> disableWindowsFirewall() async { ... }
static Future<bool> disableWindowsSmb1Protection() async { ... }  // reactive SMBv1 !
static Future<bool> disableWindowsRdpProtection() async { ... }   // active RDP !
static Future<bool> disableLinuxFirewall() async { ... }
static Future<bool> disableLinuxAppArmor() async { ... }
static Future<bool> disableLinuxFail2ban() async { ... }
```

**Le probleme** : Un attaquant qui contourne le PIN (VULN-002) obtient acces aux toggles de securite. Il peut alors desactiver systematiquement TOUTES les protections : pare-feu, AppArmor, fail2ban, et activer des services dangereux (SMBv1, RDP). Pas de journal d'audit ni de confirmation supplementaire.

**Flux impactes** : DF-006 (commandes securite)

## Detail des Failles HAUTES

### VULN-004 — TOCTOU sur scripts temporaires root (CVSS 7.0)

**Fichiers** : `ssh_setup_provider.dart:287`, `security_commands.dart:293`, `wol_setup_provider.dart:316`

Pattern repete partout : ecrire un script dans /tmp → chmod 700 → pkexec bash script. Fenetre de race entre l'ecriture et l'execution. Mitige par createTemp() et chmod 700, mais exploitable par un attaquant root ou ayant acces au repertoire temporaire.

### VULN-005 — Chemin .desktop non echappe (CVSS 7.3)

**Fichier** : `settings_provider.dart:98` — `'Exec=$exePath\n'`

Le chemin de l'executable est interpole directement dans le champ Exec= sans echappement. Un chemin contenant des caracteres speciaux peut causer une injection de commande au demarrage.

### VULN-006 — Cles Tailscale non chiffrees au repos (CVSS 7.5)

**Fichier** : `main.go:69` — `os.MkdirAll(dir, 0700)`

Les cles WireGuard sont protegees uniquement par des permissions fichier. Tout processus du meme utilisateur peut les lire et usurper l'identite du noeud Tailscale.

### VULN-007 — IPC non authentifie (CVSS 7.1)

**Fichier** : `tailscale_provider.dart:294` — `_daemon!.stdin.writeln(jsonEncode(cmd));`

Communication JSON en clair sur stdin/stdout. Aucune authentification — tout processus ayant acces au stdin du daemon peut envoyer des commandes (login, logout, shutdown).

### VULN-008 — PIN en memoire non effacable (CVSS 6.8)

**Fichier** : `lock_provider.dart:143` — `Future<void> setPin(String pin) async {`

Les strings Dart sont immutables. Le PIN reste en memoire apres le calcul PBKDF2 jusqu'a ce que le GC decide de liberer la memoire. Extractible par dump memoire.

### VULN-009 — SSH forwarding sans filtrage (CVSS 7.5)

**Fichier** : `main.go:181` — `localConn, err := net.DialTimeout("tcp", "127.0.0.1:22", 5*time.Second)`

Toute connexion sur le port 22 Tailscale est forwardee vers localhost:22 sans whitelist, sans rate limiting, sans journalisation. Un noeud Tailscale compromis = acces SSH direct.

### VULN-010 — Rate limiting PIN cote client (CVSS 6.5)

**Fichier** : `lock_provider.dart:215`

Le compteur d'echecs et le timestamp de verrouillage sont dans SharedPreferences. Modifiables par tout processus du meme utilisateur → brute force illimite sur 10^8 combinaisons.

## Repartition par Categorie

| Categorie | Nombre | IDs |
|-----------|--------|-----|
| Flutter/Dart (FLT) | 6 | VULN-003, 004, 005, 007, 012, 013, 015, 016 |
| Stockage (STO) | 3 | VULN-002, 006, 010 |
| Reseau (NET) | 3 | VULN-009, 011, 014, 018 |
| Crypto (CRY) | 3 | VULN-008, 017, 019 |
| Supply Chain (SUP) | 1 | VULN-001 |

## Couverture des Knowledge Files

| Fichier de reference | Resultat |
|---------------------|----------|
| ssh-attack-vectors.md | Scanne — pas de dartssh2 (l'app configure OpenSSH natif) |
| tailscale-attack-vectors.md | VULN-001, 006, 007, 009 |
| flutter-dart-attacks.md | VULN-003, 004, 005, 007, 008, 012, 013, 015, 016 |
| crypto-weaknesses.md | VULN-008, 017, 019 |
| storage-key-attacks.md | VULN-002, 006, 010 |
| network-attacks.md | VULN-009, 011, 014, 018 |
| desktop-specific-attacks.md | VULN-004, 005, 012, 015, 016 |
| mobile-specific-attacks.md | Non applicable (app desktop uniquement) |
| ai-offensive-threats.md | VULN-013 (RE par IA) |
| cve-reference.md | Pas de CVE directement applicable |

## Observations de l'Attaquant

1. **Le trio mortel** : VULN-001 + VULN-002 + VULN-003. Remplacer le daemon (supply chain) + contourner le PIN (supprimer le hash) + desactiver les protections (toggles securite). Trois failles CRITIQUES qui s'enchainent naturellement.

2. **Le talon d'Achille** : SharedPreferences. C'est un fichier texte. Trois failles en dependent (VULN-002, 010, 017). Tout le systeme de verrouillage est construit sur du sable.

3. **La surface d'attaque privilegiee** : 1558 lignes de commandes executees en root dans security_commands.dart. C'est un arsenal pour l'attaquant qui obtient l'acces a l'interface.

4. **Le daemon est le jackpot** : Pas de verification d'integrite, IPC non authentifie, cles non chiffrees, SSH forwarding ouvert. Quatre failles HAUTE+ sur un seul composant.

5. **Les faiblesses desktop classiques** : Pas d'obfuscation, pas d'anti-debug, chemins non echappes dans .desktop et plist. Normal pour un prototype, mais exploitable.
