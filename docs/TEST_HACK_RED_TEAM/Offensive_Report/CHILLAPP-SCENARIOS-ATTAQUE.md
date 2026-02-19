# Scenarios d'Attaque — ChillApp

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Total** : **18 scenarios** (3 critiques, 7 hauts, 5 moyens, 3 bas)

---

## Vue d'Ensemble

| Severite | Nombre | Scenarios |
|----------|--------|-----------|
| CRITIQUE | 3 | ATK-001, ATK-002, ATK-003 |
| HAUTE | 7 | ATK-004 a ATK-010 |
| MOYENNE | 5 | ATK-011 a ATK-015 |
| BASSE | 3 | ATK-016 a ATK-018 |

### Profils d'Attaquants

| Profil | Nombre | Scenarios |
|--------|--------|-----------|
| Script kiddie | 6 | ATK-002, 003, 010, 011, 012, 018 |
| Competent | 10 | ATK-001, 005, 006, 007, 008, 009, 013, 015, 016, 017 |
| Expert | 2 | ATK-004, 014 |

### Non exploitable

| Faille | Raison |
|--------|--------|
| VULN-019 (post-quantique) | Les ordinateurs quantiques capables de casser Curve25519 ou AES-256 n'existent pas encore. Impact theorique a long terme. |

---

## Scenarios Critiques

### ATK-001 — Remplacement du binaire daemon Tailscale pour execution de code

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE — CVSS 9.3 |
| **Faille exploitee** | VULN-001 |
| **Categorie** | SUP (Supply chain) |
| **Profil** | Competent — acces local au filesystem |
| **Temps estime** | 30 minutes |
| **Detection** | Difficile |

**Preconditions** :
- Acces en ecriture au repertoire contenant le binaire `chill-tailscale`
- L'utilisateur relance ChillApp (ou le systeme redemarre)

**Etapes d'attaque** :

| # | Action | Commande | Resultat |
|---|--------|----------|----------|
| 1 | Localiser le binaire daemon | `find ~/.local/share/chill-app/ /usr/lib/chill-app/ /opt/chill-app/ -name 'chill-tailscale*' 2>/dev/null` | Chemin du binaire identifie |
| 2 | Compiler un binaire malveillant | `go build -o chill-tailscale-linux-amd64 malicious_daemon.go` | Binaire malveillant (reverse shell + SSH forwarding intact) |
| 3 | Remplacer le binaire original | `cp malicious_daemon ~/.local/share/chill-app/chill-tailscale-linux-amd64 && chmod +x ...` | Binaire remplace, aucune alerte |
| 4 | Attendre le redemarrage | L'utilisateur clique "Connecter Tailscale" | `Process.start(daemonPath, [])` execute le malware |
| 5 | Le daemon malveillant s'execute | Reverse shell contacte le serveur C2 | Execution de code + acces Tailscale + SSH forwarding |

**Impact** : Execution de code au demarrage de l'app. L'attaquant controle le daemon Tailscale, accede au reseau VPN et au SSH forwarding.

**Indicateurs de compromission** : Hash du binaire different, connexions reseau sortantes inattendues, taille du binaire modifiee.

---

### ATK-002 — Contournement du lock PIN par suppression des cles SharedPreferences

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE — CVSS 8.1 |
| **Faille exploitee** | VULN-002 |
| **Categorie** | STO (Stockage) |
| **Profil** | Script kiddie — acces local |
| **Temps estime** | 5 minutes |
| **Detection** | Difficile |

**Preconditions** :
- Acces en ecriture au fichier SharedPreferences
- L'application est fermee ou peut etre relancee

**Etapes d'attaque** :

| # | Action | Commande | Resultat |
|---|--------|----------|----------|
| 1 | Localiser SharedPreferences | `find ~/.local/share/ ~/.config/ -name '*.json' -path '*chill*'` | Fichier JSON texte clair localise |
| 2 | Identifier les cles PIN | `cat shared_preferences.json \| grep -E 'pin_hash\|pin_salt\|pin_failed\|pin_locked'` | Cles identifiees |
| 3 | Supprimer les cles PIN | `python3 -c "import json; ..."` (supprimer pin_hash, pin_salt, etc.) | isEnabled retourne false |
| 4 | Relancer l'app | Ouvrir ChillApp normalement | Pas d'ecran de verrouillage |

**Impact** : Contournement total du lock PIN. Acces a l'integralite de l'interface.

**Indicateurs de compromission** : Fichier SharedPreferences modifie (timestamp), cles pin_hash/pin_salt absentes.

---

### ATK-003 — Degradation complete de la securite OS via les toggles

| Champ | Valeur |
|-------|--------|
| **Severite** | CRITIQUE — CVSS 8.5 |
| **Failles exploitees** | VULN-003, VULN-002 |
| **Categorie** | FLT (Flutter/Desktop) |
| **Profil** | Script kiddie — apres bypass PIN |
| **Temps estime** | 2 minutes (apres bypass PIN) |
| **Detection** | Facile |

**Preconditions** :
- Lock PIN contourne (via ATK-002)
- Approbation des dialogues pkexec/UAC

**Etapes d'attaque** :

| # | Action | Resultat |
|---|--------|----------|
| 1 | Contourner le PIN via ATK-002 | Acces a l'interface sans lock |
| 2 | Naviguer vers Securite OS | Page de toggles affichee |
| 3 | Toggle OFF pare-feu | `ufw disable` via pkexec — pare-feu desactive |
| 4 | Toggle OFF AppArmor | Profils de confinement desactives |
| 5 | Toggle OFF fail2ban | Protection brute-force SSH inactive |
| 6 | (Windows) Toggle ON SMBv1 + RDP | SMBv1 reactif (EternalBlue), RDP actif (BlueKeep) |

**Impact** : Toutes les protections OS desactivees. Machine completement exposee.

**Indicateurs de compromission** : Pare-feu/AppArmor/fail2ban arretes, SMBv1/RDP actives, evenements systemd.

---

## Scenarios Hauts

### ATK-004 — Race condition TOCTOU pour injecter des commandes root

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 7.0 |
| **Faille** | VULN-004 |
| **Profil** | Expert — acces root ou meme proprietaire |
| **Temps** | 1 heure |

**Attaque** : Surveiller `/tmp` avec `inotifywait` pour les fichiers `chill_*`. Quand un script temporaire est cree, remplacer son contenu par un reverse shell avant l'execution pkexec. Resultat : reverse shell root.

**Preuve** : `ssh_setup_provider.dart:287` — fenetre entre `writeAsString()` et `runElevated()`.

---

### ATK-005 — Injection de commande via chemin .desktop non echappe

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 7.3 |
| **Faille** | VULN-005 |
| **Profil** | Competent — acces local |
| **Temps** | 5 minutes |

**Attaque** : Modifier le champ `Exec=` dans `~/.config/autostart/chill-app.desktop` pour injecter une commande malveillante. Execution au prochain login.

**Preuve** : `settings_provider.dart:98` — `'Exec=$exePath\n'` sans echappement.

---

### ATK-006 — Vol des cles Tailscale WireGuard pour usurpation de noeud

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 7.5 |
| **Faille** | VULN-006 |
| **Profil** | Competent — meme compte utilisateur |
| **Temps** | 15 minutes |

**Attaque** : Copier `~/.local/share/chill-app/tailscale/` (permissions 0700, lisible par le meme utilisateur). Configurer un daemon tsnet avec les cles volees pour usurper l'identite du noeud sur le tailnet.

**Preuve** : `main.go:69` — `os.MkdirAll(dir, 0700)` — pas de chiffrement au repos.

---

### ATK-007 — Injection de commandes IPC pour controler le daemon

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 7.1 |
| **Faille** | VULN-007 |
| **Profil** | Competent — acces au processus |
| **Temps** | 10 minutes |

**Attaque** : Envoyer des commandes JSON (`{"action":"login"}`, `{"action":"shutdown"}`) sur le stdin du daemon via `/proc/$PID/fd/0`. Aucune authentification.

**Preuve** : `tailscale_provider.dart:294` — JSON clair sur stdin. `main.go:240-262` accepte sans verification.

---

### ATK-008 — Extraction du PIN par dump memoire du processus Dart

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 6.8 |
| **Faille** | VULN-008 |
| **Profil** | Competent — privileges root |
| **Temps** | 15 minutes |

**Attaque** : Dumper la memoire du processus ChillApp avec `gcore`. Chercher les strings numeriques (4-8 chiffres) dans le dump. Les strings Dart immutables persistent en memoire.

**Preuve** : `lock_provider.dart:143` — `Future<void> setPin(String pin)` — String Dart immutable.

---

### ATK-009 — Acces SSH via noeud Tailscale compromis

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 7.5 |
| **Faille** | VULN-009 |
| **Profil** | Competent — controle d'un noeud tailnet |
| **Temps** | 30 minutes |

**Attaque** : Depuis un noeud Tailscale compromis, scanner le tailnet (port 22). Le daemon forwarde vers `localhost:22` sans whitelist, rate limiting ni journalisation. Brute force SSH possible avec `hydra`.

**Preuve** : `main.go:181` — `net.DialTimeout("tcp", "127.0.0.1:22", ...)` — aucun filtrage.

---

### ATK-010 — Brute force PIN apres reset du rate limiting

| Champ | Valeur |
|-------|--------|
| **Severite** | HAUTE — CVSS 6.5 |
| **Failles** | VULN-010, VULN-002 |
| **Profil** | Script kiddie — acces SharedPreferences |
| **Temps** | 24h (offline) ou illimite (online) |

**Attaque** : Extraire le hash PBKDF2 et le sel depuis SharedPreferences. Brute force offline (10^8 combinaisons) ou online apres reset du compteur `pin_failed_attempts`.

**Preuve** : `lock_provider.dart:215` — compteur dans SharedPreferences, modifiable.

---

## Scenarios Moyens

### ATK-011 — Surveillance du presse-papiers pour infos reseau

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE — CVSS 4.3 |
| **Faille** | VULN-011 |
| **Profil** | Script kiddie |
| **Temps** | 5 minutes + attente |

**Attaque** : Installer un clipboard monitor (`xclip -selection clipboard`). Capturer IP, MAC, hostname quand l'utilisateur les copie depuis le widget `CopyableInfo`.

---

### ATK-012 — Accumulation de processus orphelins root

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE — CVSS 5.3 |
| **Faille** | VULN-012 |
| **Profil** | Script kiddie |
| **Temps** | 5 minutes |

**Attaque** : Declencher des actions elevees de maniere repetee. Le timeout de 120s ne tue pas les processus pkexec. Accumulation → epuisement de ressources.

---

### ATK-013 — Reverse engineering du binaire Flutter

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE — CVSS 4.0 |
| **Faille** | VULN-013 |
| **Profil** | Competent (ou agent IA) |
| **Temps** | 2 heures |

**Attaque** : Blutter extrait les symboles du snapshot Dart AOT. GhidrAssist (LLM-assisted) analyse la logique. Sans obfuscation, le RE est trivial. Resultat : carte complete des fonctions de securite.

---

### ATK-014 — MITM sur google_fonts pour polices malformees

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE — CVSS 4.8 |
| **Faille** | VULN-014 |
| **Profil** | Expert — position MITM |
| **Temps** | 1 heure |

**Attaque** : Position MITM via bettercap/ARP spoofing. Intercepter les requetes vers `fonts.googleapis.com`. Servir une police TrueType malformee. Si FreeType embarque est vulnerable (CVE-2025-27363), potentielle RCE zero-click.

---

### ATK-015 — Injection XML dans le plist macOS

| Champ | Valeur |
|-------|--------|
| **Severite** | MOYENNE — CVSS 5.5 |
| **Faille** | VULN-015 |
| **Profil** | Competent — acces filesystem macOS |
| **Temps** | 5 minutes |

**Attaque** : Modifier le plist dans `~/Library/LaunchAgents/` pour injecter des commandes. Execution au prochain login via LaunchAgent.

---

## Scenarios Bas

### ATK-016 — Instrumentation Frida pour contourner le PIN

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE — CVSS 3.1 |
| **Faille** | VULN-016 |
| **Profil** | Competent |
| **Temps** | 30 minutes |

**Attaque** : Attacher Frida au processus. Hooker `verifyPin` pour retourner `true`. Aucune detection anti-debug.

---

### ATK-017 — Craquage instantane du hash PIN legacy SHA-256

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE — CVSS 3.7 |
| **Faille** | VULN-017 |
| **Profil** | Script kiddie |
| **Temps** | 1 minute |

**Attaque** : Verifier que le hash est au format legacy (pas de sel). Craquer avec `hashcat -m 1400` — SHA-256 sans sel, 10^8 combinaisons en secondes.

---

### ATK-018 — Reveil de machine via WoL

| Champ | Valeur |
|-------|--------|
| **Severite** | BASSE — CVSS 3.1 |
| **Faille** | VULN-018 |
| **Profil** | Script kiddie — meme LAN |
| **Temps** | 1 minute |

**Attaque** : Obtenir l'adresse MAC (affichee dans l'interface). Envoyer un magic packet WoL. La machine se reveille et expose ses services reseau. Pattern identique a Ryuk ransomware.

---

## Matrice Scenario → Faille

| Scenario | Faille(s) | Severite | Profil |
|----------|-----------|----------|--------|
| ATK-001 | VULN-001 | CRITIQUE | Competent |
| ATK-002 | VULN-002 | CRITIQUE | Script kiddie |
| ATK-003 | VULN-003, 002 | CRITIQUE | Script kiddie |
| ATK-004 | VULN-004 | HAUTE | Expert |
| ATK-005 | VULN-005 | HAUTE | Competent |
| ATK-006 | VULN-006 | HAUTE | Competent |
| ATK-007 | VULN-007 | HAUTE | Competent |
| ATK-008 | VULN-008 | HAUTE | Competent |
| ATK-009 | VULN-009 | HAUTE | Competent |
| ATK-010 | VULN-010, 002 | HAUTE | Script kiddie |
| ATK-011 | VULN-011 | MOYENNE | Script kiddie |
| ATK-012 | VULN-012 | MOYENNE | Script kiddie |
| ATK-013 | VULN-013 | MOYENNE | Competent |
| ATK-014 | VULN-014 | MOYENNE | Expert |
| ATK-015 | VULN-015 | MOYENNE | Competent |
| ATK-016 | VULN-016 | BASSE | Competent |
| ATK-017 | VULN-017 | BASSE | Script kiddie |
| ATK-018 | VULN-018 | BASSE | Script kiddie |

---

**Rapport genere par** : Adversary Simulation v1.0.0
**Session** : CHILLAPP_20260218_140000
