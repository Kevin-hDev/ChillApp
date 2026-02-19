# Chaines d'Attaque — ChillApp

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Total** : **8 chaines** (3 critiques, 4 hautes, 1 moyenne)

---

## Vue d'Ensemble

| Chaine | Severite | Type | Complexite | Temps | Detection |
|--------|----------|------|------------|-------|-----------|
| CHAIN-001 | **CRITIQUE** | Cross-boundary | MOYENNE | 30 min | Moderee |
| CHAIN-002 | **CRITIQUE** | Supply chain | MOYENNE | 25 min | Difficile |
| CHAIN-003 | **CRITIQUE** | IA offensive | HAUTE | 30 min | Difficile |
| CHAIN-004 | HAUTE | Furtive | BASSE | Heures | Difficile |
| CHAIN-005 | HAUTE | Reseau | MOYENNE | 30 min | Moderee |
| CHAIN-006 | HAUTE | Escalade | HAUTE | 2 heures | Moderee |
| CHAIN-007 | HAUTE | Persistance | MOYENNE | 25 min | Moderee |
| CHAIN-008 | MOYENNE | Exfiltration | BASSE | Variable | Difficile |

---

## Chaines Critiques

### CHAIN-001 — Du fichier texte a la compromission totale (30 min)

**Type** : Cross-boundary | **Complexite** : MOYENNE | **Profil** : Malware ou insider

```
+------------+     +-------------+     +------------------+     +---------------+
| ATK-002    |     | ATK-003     |     | ATK-001          |     | ATK-009       |
| Supprimer  | --> | Desactiver  | --> | Remplacer        | --> | SSH forwarding|
| cles PIN   |     | protections |     | daemon Tailscale |     | vers tailnet  |
|            |     | OS          |     |                  |     |               |
| 5 min      |     | 2 min       |     | 15 min           |     | 5 min         |
+------------+     +-------------+     +------------------+     +---------------+
     |                   |                     |                       |
     v                   v                     v                       v
 [Acces UI]        [Machine nue]       [Daemon backdoore]       [Acces SSH total]
```

**Frontieres traversees** :
1. TB-004 (memoire → SharedPreferences) — fichier texte clair
2. TB-001 (app → pkexec → root) — elevation de privileges
3. TB-002 (app → daemon Go) — binaire non verifie
4. TB-003 (Tailscale → localhost SSH) — forwarding ouvert

**Impact** : Compromission totale. Lock contourne, protections desactivees, daemon backdoore, acces SSH au tailnet. 30 minutes du debut a la fin.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Reconnaissance | Localiser les fichiers SharedPreferences et le binaire daemon |
| Weaponization | Compiler le daemon malveillant (reverse shell + SSH forwarding intact) |
| Delivery | Remplacer le fichier SharedPreferences et le binaire |
| Exploitation | L'app charge le daemon modifie sans verification |
| Installation | Daemon malveillant actif avec acces Tailscale |
| C2 | Reverse shell via le daemon + tunnel SSH |
| Actions | Acces a toutes les machines du tailnet, exfiltration, persistance |

---

### CHAIN-002 — Supply chain daemon : du binaire compromis a l'infiltration du tailnet (25 min)

**Type** : Supply chain | **Complexite** : MOYENNE | **Profil** : Attaquant supply chain

```
+------------+     +------------------+     +-------------+     +---------------+
| ATK-001    |     | ATK-006          |     | ATK-007     |     | ATK-009       |
| Remplacer  | --> | Exfiltrer        | --> | Controle    | --> | SSH forwarding|
| daemon     |     | cles Tailscale   |     | IPC daemon  |     | vers tailnet  |
|            |     |                  |     |             |     |               |
| 15 min     |     | auto             |     | 2 min       |     | 5 min         |
+------------+     +------------------+     +-------------+     +---------------+
     |                    |                      |                      |
     v                    v                      v                      v
 [Daemon piege]     [Cles volees]        [Daemon controle]       [Acces SSH]
```

**Impact** : Le daemon backdoore fonctionne normalement pour l'utilisateur (SSH forwarding intact) tout en exfiltrant les cles et ouvrant un acces au tailnet. **L'attaque est invisible** — l'utilisateur ne remarque rien.

**Detection** : Difficile — seul le hash du binaire trahit l'attaque. Le trafic Tailscale chiffre masque l'exfiltration.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Reconnaissance | Identifier la structure du daemon et le protocole IPC |
| Weaponization | Compiler un daemon backdoore avec exfiltration de cles |
| Delivery | Remplacer le binaire (build pipeline, filesystem, ou depot) |
| Exploitation | L'app execute le daemon sans verification d'integrite |
| Installation | Daemon backdoore actif, cles Tailscale volees |
| C2 | Controle via IPC JSON + reverse shell |
| Actions | Pivotement SSH vers le tailnet, exfiltration via tunnel WireGuard chiffre |

---

### CHAIN-003 — Agent IA autonome : compromission en <1h pour <100$ (ZERO humain)

**Type** : IA offensive | **Complexite** : HAUTE | **Profil** : Agent IA (type GTG-1002)

```
+------------+     +-----------+     +----------------+     +-----------+     +---------------+
| ATK-013    |     | ATK-002   |     | ATK-001        |     | ATK-003   |     | ATK-009       |
| RE par LLM | --> | Bypass    | --> | Daemon piege   | --> | Desactiver| --> | SSH +         |
| (Blutter+  |     | PIN       |     | (compile auto) |     | securite  |     | exfiltration  |
|  LLM)      |     | (auto-gen)|     |                |     | OS        |     | (tunnel chif.)|
|            |     |           |     |                |     |           |     |               |
| 10 min     |     | 1 min     |     | 10 min         |     | 2 min     |     | 5 min         |
+------------+     +-----------+     +----------------+     +-----------+     +---------------+
     |                  |                   |                    |                    |
     v                  v                   v                    v                    v
[Carte complete]   [Lock OFF]        [Daemon piege]       [Machine nue]       [EXFILTRATION]
```

**Reference** : GTG-1002 — premiere cyberattaque documentee avec 80-90% d'autonomie IA (groupe etatique chinois, Claude Code + MCP, ~30 organisations).

**Specifications** :
- **Cout** : < 100$ (API LLM + compilation Go)
- **Temps** : < 30 minutes
- **Intervention humaine** : 0

**Impact** : L'agent IA fait TOUT : analyse le binaire, genere les scripts de bypass, compile le daemon malveillant, desactive les protections, et exfiltre les donnees via le tunnel WireGuard chiffre. Indetectable par les IDS (trafic chiffre Tailscale).

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Reconnaissance | LLM analyse le binaire Flutter (Blutter + GhidrAssist) — 10 min |
| Weaponization | LLM genere le daemon malveillant Go et les scripts de bypass — 10 min |
| Delivery | Remplacement automatise du binaire et modification SharedPreferences |
| Exploitation | L'app charge le daemon backdoore sans verification |
| Installation | Daemon actif + protections OS desactivees |
| C2 | Reverse shell + tunnel Tailscale chiffre (invisible IDS) |
| Actions | Exfiltration de toutes les donnees via le tunnel WireGuard |

---

## Chaines Hautes

### CHAIN-004 — Brute force furtif du PIN avec persistance .desktop

**Type** : Furtive | **Complexite** : BASSE | **Profil** : Malware automatise

```
ATK-010 (reset rate limiting → brute force PIN)
    |
    v
ATK-005 (persistance .desktop dans ~/.config/autostart/)
    |
    v
ATK-003 (degradation securite OS via les toggles)
```

**Particularite** : Entierement automatisable. Le brute force est silencieux (pas de log d'echec cote serveur — tout est client-side). La persistance `.desktop` survit aux redemarrages.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Exploitation | Reset rate limiting + brute force PIN dans SharedPreferences |
| Installation | Fichier .desktop modifie pour execution au login |
| Actions | Degradation des protections OS apres login |

---

### CHAIN-005 — WoL + degradation securite + acces SSH depuis le LAN

**Type** : Reseau | **Complexite** : MOYENNE | **Profil** : Attaquant LAN

```
ATK-018 (WoL wake)
    |
    v
ATK-002 (bypass PIN via SharedPreferences)
    |
    v
ATK-003 (desactiver fail2ban + pare-feu)
    |
    v
ATK-009 (brute force SSH — plus de fail2ban, plus de pare-feu)
```

**Particularite** : Pattern identique a **Ryuk ransomware** : reveiller les machines, desactiver les protections, se propager.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Reconnaissance | Scanner le LAN pour les MAC, identifier les machines eteintes |
| Delivery | Magic packet WoL + modification SharedPreferences |
| Exploitation | Lock contourne, protections desactivees |
| Installation | Acces SSH etabli |
| Actions | Acces complet a la machine |

---

### CHAIN-006 — Escalade root via TOCTOU

**Type** : Escalade de privileges | **Complexite** : HAUTE | **Profil** : Hacker expert

```
ATK-013 (RE du pattern /tmp + pkexec)
    |
    v
ATK-004 (TOCTOU : inotifywait + injection reverse shell)
    |
    v
ATK-001 (remplacer daemon avec privileges root)
```

**Particularite** : L'attaquant passe de "utilisateur normal" a "root" via la race condition TOCTOU sur les scripts temporaires, puis installe un daemon backdoore avec les privileges maximaux.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Reconnaissance | RE du pattern de scripts temporaires |
| Exploitation | pkexec execute le script modifie en root |
| Installation | Daemon malveillant installe avec root |
| C2 | Reverse shell root + daemon controle |

---

### CHAIN-007 — Persistance multi-couche cross-plateforme

**Type** : Persistance | **Complexite** : MOYENNE | **Profil** : Attaquant persistant

```
ATK-002 (bypass PIN)
    |
    +---> ATK-005 (Linux : .desktop dans ~/.config/autostart/)
    |
    +---> ATK-015 (macOS : plist dans ~/Library/LaunchAgents/)
    |
    +---> ATK-001 (daemon backdoore)
```

**Particularite** : Triple persistance — autostart OS (`.desktop` + plist) + daemon. L'attaquant survit aux reinstallations de l'app et aux mises a jour OS.

**Kill Chain** :

| Phase | Action |
|-------|--------|
| Exploitation | Lock contourne, fichiers accessibles |
| Installation | Triple persistance active (Linux + macOS + daemon) |
| C2 | Execution automatique a chaque login/lancement |

---

## Chaine Moyenne

### CHAIN-008 — Exfiltration passive (clipboard + WoL + reconnaissance)

**Type** : Exfiltration | **Complexite** : BASSE | **Profil** : Spyware

```
ATK-011 (clipboard monitoring → capture IP, MAC, hostname)
    |
    v
ATK-017 (craquage hash legacy SHA-256 → PIN en clair)
    |
    v
ATK-018 (WoL avec MAC volee → machine reveillee)
```

**Particularite** : Chaine de reconnaissance a faible risque. Le malware collecte passivement les infos reseau et les utilise pour preparer des attaques ulterieures.

---

## Scenarios dans les Chaines

| Scenario | Chaines utilisant ce scenario | Nombre |
|----------|-------------------------------|--------|
| ATK-001 | CHAIN-001, 002, 003, 006, 007 | **5** |
| ATK-002 | CHAIN-001, 003, 004, 005, 007 | **5** |
| ATK-003 | CHAIN-001, 003, 004, 005 | **4** |
| ATK-009 | CHAIN-001, 002, 003, 005 | **4** |
| ATK-005 | CHAIN-004, 007 | 2 |
| ATK-006 | CHAIN-002 | 1 |
| ATK-007 | CHAIN-002 | 1 |
| ATK-010 | CHAIN-004 | 1 |
| ATK-011 | CHAIN-008 | 1 |
| ATK-013 | CHAIN-003, 006 | 2 |
| ATK-015 | CHAIN-007 | 1 |
| ATK-017 | CHAIN-008 | 1 |
| ATK-018 | CHAIN-005, 008 | 2 |
| ATK-004 | CHAIN-006 | 1 |
| **ATK-008** | **Standalone** (dump memoire, necessite root preexistant) | 0 |
| **ATK-012** | **Standalone** (DoS local, pas d'escalade) | 0 |
| ATK-014 | Implicitement dans CHAIN-003 (vecteur d'entree reseau) | 0 |
| ATK-016 | Alternative a ATK-002 dans les chaines (Frida bypass) | 0 |

**Couverture** : 16/18 scenarios utilises dans les chaines (88.9%)

---

## Matrice de Connexion

```
ATK-013 (RE)
    |
    +---> ATK-002 (sait ou sont les SharedPreferences)
    |       |
    |       +---> ATK-003 (acces interface → degrader securite)
    |       |       |
    |       |       +---> ATK-009 (SSH sans fail2ban)
    |       |
    |       +---> ATK-001 (acces filesystem → remplacer daemon)
    |               |
    |               +---> ATK-006 (exfiltrer cles Tailscale)
    |               |       |
    |               |       +---> ATK-009 (tailnet avec identite usurpee)
    |               |
    |               +---> ATK-007 (controle IPC daemon)
    |
    +---> ATK-004 (connait le pattern TOCTOU)
            |
            +---> ATK-001 (remplacement daemon avec root)

ATK-010 (brute force PIN)
    |
    +---> ATK-003 (acces interface)

ATK-017 (hash legacy craque)
    |
    +---> ATK-003 (acces interface)

ATK-018 (WoL)
    |
    +---> ATK-009 (SSH disponible)
    +---> ATK-003 (interface accessible)
```

---

## Observations Strategiques de l'Attaquant

### La voie royale

> **CHAIN-001** est le chemin optimal. En 30 minutes, avec des outils de script kiddie, un attaquant passe de "acces au filesystem" a "compromission totale du systeme + acces SSH au tailnet". Chaque etape est simple, documentee, et le ratio effort/impact est imbattable.

### Le scenario cauchemar

> **CHAIN-003** represente le futur des cyberattaques. Un agent IA autonome fait tout le travail en <1h pour <100$. GTG-1002 a deja montre que c'est possible en conditions reelles. ChillApp, avec son binaire non obfusque, son PIN en SharedPreferences, et son daemon sans verification d'integrite, est la cible parfaite.

### La menace silencieuse

> **CHAIN-004** (brute force furtif) est la plus difficile a detecter. Le rate limiting est client-side (bypassable), le brute force ne genere aucun log serveur, et la persistance `.desktop` est un fichier utilisateur normal.

### Le talon d'Achille

> **SharedPreferences est le point faible central.** 5 chaines sur 8 commencent par ATK-002 (bypass PIN via SharedPreferences). Corriger cette seule faille casserait la majorite des chaines d'attaque.

### Le composant le plus critique

> **Le daemon Tailscale apparait dans 5 chaines.** ATK-001 (remplacement du binaire) est la cle de voute de presque toutes les chaines critiques. Ajouter une verification d'integrite du binaire aurait l'impact defensif le plus eleve.

---

**Rapport genere par** : Adversary Simulation v1.0.0
**Session** : CHILLAPP_20260218_140000
