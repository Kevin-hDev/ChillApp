# P5 - Chaines d'Attaque

## Synthese

8 chaines d'attaque identifiees : 3 critiques, 4 hautes, 1 moyenne. Les chaines couvrent 8 categories (cross-boundary, supply chain, IA offensive, furtive, reseau, escalade de privileges, persistance, exfiltration). La chaine la plus dangereuse est CHAIN-003 (agent IA autonome — compromission totale en <1h pour <100$). La "voie royale" est CHAIN-001 (du fichier texte a la compromission totale en 30 minutes).

## Chaines Critiques

### CHAIN-001 : Du fichier texte a la compromission totale (30 min)

**Type** : Cross-boundary | **Complexite** : MOYENNE | **Profil** : Malware ou insider

```
ATK-002          ATK-003           ATK-001            ATK-009
Supprimer     -> Desactiver     -> Remplacer       -> SSH forwarding
cles PIN         protections OS    daemon Tailscale    vers tailnet
   |                |                 |                   |
   v                v                 v                   v
[Acces UI]     [Machine nue]    [Daemon backdoore]  [Acces SSH total]
  5 min            2 min            15 min              5 min
```

**Frontieres traversees** : TB-004 (SharedPrefs) → TB-001 (pkexec) → TB-002 (daemon) → TB-003 (SSH)

**Impact** : Compromission totale. Lock contourne, protections desactivees, daemon backdoore, acces SSH au tailnet. 30 minutes du debut a la fin.

**Detection** : Moderee — les desactivations de pare-feu generent des logs systemd.

---

### CHAIN-002 : Supply chain daemon → infiltration du tailnet (25 min)

**Type** : Supply chain | **Complexite** : MOYENNE | **Profil** : Attaquant supply chain

```
ATK-001          ATK-006          ATK-007           ATK-009
Remplacer     -> Exfiltrer     -> Controle IPC  -> SSH forwarding
daemon           cles Tailscale   du daemon        vers tailnet
   |                |                |                 |
   v                v                v                 v
[Daemon piege]  [Cles volees]   [Daemon controle] [Acces SSH]
  15 min          auto             2 min            5 min
```

**Impact** : Le daemon backdoore fonctionne normalement pour l'utilisateur (SSH forwarding intact) tout en exfiltrant les cles et ouvrant un acces au tailnet. L'attaque est invisible — l'utilisateur ne remarque rien.

**Detection** : Difficile — seul le hash du binaire trahit l'attaque. Le trafic Tailscale chiffre masque l'exfiltration.

---

### CHAIN-003 : Agent IA autonome — compromission en <1h pour <100$ (ZERO humain)

**Type** : IA offensive | **Complexite** : HAUTE | **Profil** : Agent IA (type GTG-1002)

```
ATK-013          ATK-002         ATK-001          ATK-003          ATK-009
RE par LLM    -> Bypass PIN  -> Daemon piege  -> Desactiver   -> SSH + exfiltration
(Blutter+LLM)   (auto-gen)     (compile auto)   securite OS     (tunnel chiffre)
   |                |               |               |                |
   v                v               v               v                v
[Carte complete] [Lock OFF]   [Daemon piege]  [Machine nue]   [EXFILTRATION]
   10 min          1 min         10 min          2 min            5 min
```

**Reference** : GTG-1002 — premiere cyberattaque documentee avec 80-90% d'autonomie IA (groupe etatique chinois, Claude Code + MCP, ~30 organisations).

**Cout** : < 100$ (API LLM + compilation Go)
**Temps** : < 30 minutes
**Intervention humaine** : 0

**Impact** : L'agent IA fait TOUT : analyse le binaire, genere les scripts de bypass, compile le daemon malveillant, desactive les protections, et exfiltre les donnees via le tunnel WireGuard chiffre. Indetectable par les IDS (trafic chiffre Tailscale).

## Chaines Hautes

### CHAIN-004 : Brute force furtif + persistance .desktop

**Type** : Furtive | **Complexite** : BASSE

ATK-010 (reset rate limiting → brute force PIN) → ATK-005 (persistance .desktop) → ATK-003 (degradation securite)

Entierement automatisable par un malware. Le brute force est silencieux (pas de log d'echec cote serveur — tout est client-side). La persistance .desktop survit aux redemarrages.

### CHAIN-005 : WoL + degradation securite + SSH depuis le LAN

**Type** : Reseau | **Complexite** : MOYENNE

ATK-018 (WoL wake) → ATK-002 (bypass PIN) → ATK-003 (desactiver fail2ban + pare-feu) → ATK-009 (SSH brute force)

Pattern identique a **Ryuk ransomware** : reveiller les machines, desactiver les protections, se propager. La combinaison WoL + desactivation fail2ban rend le SSH brute force trivial.

### CHAIN-006 : Escalade root via TOCTOU

**Type** : Escalade de privileges | **Complexite** : HAUTE

ATK-013 (comprendre le pattern /tmp) → ATK-004 (TOCTOU → root shell) → ATK-001 (remplacer daemon avec root)

L'attaquant passe de "utilisateur normal" a "root" via la race condition TOCTOU sur les scripts temporaires, puis installe un daemon backdoore avec les privileges maximaux.

### CHAIN-007 : Persistance multi-couche cross-plateforme

**Type** : Persistance | **Complexite** : MOYENNE

ATK-002 (bypass PIN) → ATK-005 (Linux .desktop) + ATK-015 (macOS plist) + ATK-001 (daemon backdoore)

Triple persistance : autostart OS + daemon. L'attaquant survit aux reinstallations de l'app et aux mises a jour OS.

## Chaine Moyenne

### CHAIN-008 : Exfiltration passive (clipboard + WoL + reconnaissance)

**Type** : Exfiltration | **Complexite** : BASSE

ATK-011 (clipboard monitoring) → ATK-017 (craquage hash legacy) → ATK-018 (WoL avec MAC volee)

Chaine de reconnaissance a faible risque. Le malware collecte passivement les infos reseau et les utilise pour preparer des attaques ulterieures.

## Matrice d'Impact

| Chaine | Severite | Complexite | Type | Temps | Detection |
|--------|----------|------------|------|-------|-----------|
| CHAIN-001 | **CRITIQUE** | MOYENNE | Cross-boundary | 30 min | Moderee |
| CHAIN-002 | **CRITIQUE** | MOYENNE | Supply chain | 25 min | Difficile |
| CHAIN-003 | **CRITIQUE** | HAUTE | IA offensive | 30 min | Difficile |
| CHAIN-004 | HAUTE | BASSE | Furtive | Heures | Difficile |
| CHAIN-005 | HAUTE | MOYENNE | Reseau | 30 min | Moderee |
| CHAIN-006 | HAUTE | HAUTE | Escalade | 2 heures | Moderee |
| CHAIN-007 | HAUTE | MOYENNE | Persistance | 25 min | Moderee |
| CHAIN-008 | MOYENNE | BASSE | Exfiltration | Variable | Difficile |

## Scenarios dans les Chaines

| ATK | Chaines utilisant ce scenario |
|-----|-------------------------------|
| ATK-001 | CHAIN-001, 002, 003, 006, 007 |
| ATK-002 | CHAIN-001, 003, 004, 005, 007 |
| ATK-003 | CHAIN-001, 003, 004, 005 |
| ATK-004 | CHAIN-006 |
| ATK-005 | CHAIN-004, 007 |
| ATK-006 | CHAIN-002 |
| ATK-007 | CHAIN-002 |
| ATK-009 | CHAIN-001, 002, 003, 005 |
| ATK-010 | CHAIN-004 |
| ATK-011 | CHAIN-008 |
| ATK-013 | CHAIN-003, 006 |
| ATK-015 | CHAIN-007 |
| ATK-017 | CHAIN-008 |
| ATK-018 | CHAIN-005, 008 |
| **ATK-008** | **Standalone** (dump memoire, necessite root preexistant) |
| **ATK-012** | **Standalone** (DoS local, pas d'escalade) |
| ATK-014 | Utilise implicitement dans CHAIN-003 (vecteur d'entree reseau) |
| ATK-016 | Alternative a ATK-002 dans les chaines (Frida bypass) |

## Observations Strategiques de l'Attaquant

### La voie royale

> **CHAIN-001** est le chemin optimal. En 30 minutes, avec des outils de script kiddie, un attaquant passe de "acces au filesystem" a "compromission totale du systeme + acces SSH au tailnet". Chaque etape est simple, documentee, et le ratio effort/impact est imbattable.

### Le scenario cauchemar

> **CHAIN-003** represente le futur des cyberattaques. Un agent IA autonome fait tout le travail en <1h pour <100$. GTG-1002 a deja montre que c'est possible en conditions reelles. ChillApp, avec son binaire non obfusque, son PIN en SharedPreferences, et son daemon sans verification d'integrite, est la cible parfaite.

### La menace silencieuse

> **CHAIN-004** (brute force furtif) est la plus difficile a detecter. Le rate limiting est client-side (bypassable), le brute force ne genere aucun log serveur, et la persistance .desktop est un fichier utilisateur normal. Un malware patient peut craquer le PIN sans jamais alerter.

### Le point commun

> **SharedPreferences est le talon d'Achille**. 5 chaines sur 8 commencent par ATK-002 (bypass PIN via SharedPreferences). Corriger cette seule faille casserait la majorite des chaines d'attaque.

### Le composant le plus critique

> **Le daemon Tailscale apparait dans 5 chaines**. ATK-001 (remplacement du binaire) est la cle de voute de presque toutes les chaines critiques. Ajouter une verification d'integrite du binaire aurait l'impact defensif le plus eleve.
