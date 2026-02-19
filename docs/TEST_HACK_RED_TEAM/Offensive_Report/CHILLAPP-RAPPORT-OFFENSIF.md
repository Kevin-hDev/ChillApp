# Rapport Offensif — ChillApp

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Methodologie** : Adversary Simulation v1.0.0 — 6 phases
**Niveau de risque global** : CRITIQUE

---

## 1. Synthese Executive

### Chiffres Cles

| Metrique | Valeur |
|----------|--------|
| Points d'entree identifies | **16** |
| Flux de donnees traces | **12** |
| Secrets en transit | **6** |
| Vulnerabilites decouvertes | **19** (3 critiques, 7 hautes) |
| Scenarios d'attaque concrets | **18** |
| Chaines d'attaque multi-etapes | **8** (3 critiques) |

### Top 3 des Risques

1. **Binaire daemon Tailscale sans verification d'integrite** (CVSS 9.3) — Un attaquant qui remplace le binaire obtient une execution de code au demarrage, avec acces au reseau VPN et au SSH forwarding.

2. **PIN stocke dans un fichier texte clair** (CVSS 8.1) — Supprimer deux cles dans SharedPreferences desactive completement le lock. 5 minutes, zero outil special.

3. **Module securite peut desactiver TOUTES les protections OS** (CVSS 8.5) — Les toggles permettent de desactiver pare-feu, AppArmor, fail2ban et d'activer SMBv1/RDP. Pas de journal d'audit.

### Recommandation Principale

> **Remplacer SharedPreferences par un stockage chiffre au repos** (libsecret sur Linux, Credential Manager sur Windows, Keychain sur macOS) ET **ajouter une verification d'integrite du binaire daemon** (checksum SHA-256 ou signature). Ces deux corrections casseraient 7 des 8 chaines d'attaque identifiees.

---

## 2. Methodologie

La simulation offensive a ete conduite en 6 phases sequentielles :

| Phase | Nom | Objectif | Resultat |
|-------|-----|----------|----------|
| P1 | Reconnaissance | Identifier le stack et les surfaces d'attaque | 8 cibles, 16 points d'entree |
| P2 | Cartographie des flux | Tracer les flux de donnees sensibles | 12 flux, 6 secrets, 5 frontieres |
| P3 | Chasse aux failles | Analyser le code ligne par ligne | 19 vulnerabilites |
| P4 | Construction des attaques | Creer des scenarios d'exploitation concrets | 18 scenarios |
| P5 | Chaines d'attaque | Combiner les attaques en sequences | 8 chaines multi-etapes |
| P6 | Rapport | Synthetiser et prioriser | Ce rapport |

Chaque faille est prouvee par une reference exacte dans le code source (fichier:ligne).

---

## 3. Surface d'Attaque

### Stack Technique

| Composant | Version | Risque |
|-----------|---------|--------|
| Flutter | 3.38.7 | BASSE |
| Dart | 3.10.7 | BASSE |
| shared_preferences | ^2.5.4 | **CRITIQUE** — texte clair |
| crypto | ^3.0.7 | HAUTE — implementation custom |
| tsnet (Go daemon) | latest | **CRITIQUE** — binaire non verifie |
| google_fonts | ^8.0.1 | BASSE — telecharge runtime |

### Matrice de la Surface d'Attaque

| Categorie | Elements | Niveau |
|-----------|----------|--------|
| Reseau | SSH:22, Tailscale/WireGuard:41641, WoL:9 | CRITIQUE |
| Stockage | SharedPreferences (texte clair), Tailscale state dir | CRITIQUE |
| Crypto | PBKDF2 custom, SHA-256 legacy | HAUTE |
| Desktop | Pas de sandbox, elevation privileges, scripts /tmp | CRITIQUE |
| Supply Chain | 3 binaires Go non signes (~100Mo) | HAUTE |

---

## 4. Flux de Donnees Critiques

```
Utilisateur
    |
    v
+------------------+         +------------------+
| UI Flutter       |--PIN-->| SharedPreferences | (texte clair!)
| (lock_screen)    |        | (disque)          |
+------------------+         +------------------+
    |
    |--IPC JSON clair-->+------------------+
    |                   | Daemon Go        |--SSH fwd-->localhost:22
    |                   | (chill-tailscale)|
    |                   +------------------+
    |
    |--scripts /tmp-->[pkexec]-->Config systeme (SSH, pare-feu, DNS)
    |
    +--state-->~/.local/share/chill-app/tailscale/ (cles WireGuard)
```

**Frontieres de confiance les plus faibles** :
- TB-004 (memoire → SharedPreferences) : **AUCUNE protection** — fichier texte lisible/modifiable
- TB-002 (app → daemon Go) : **AUCUNE authentification** — IPC JSON clair, binaire non verifie

---

## 5. Failles Decouvertes (Top 10)

| # | ID | Titre | Severite | CVSS | Fichier:Ligne |
|---|-----|-------|----------|------|---------------|
| 1 | VULN-001 | Daemon binaire sans verification integrite | **CRITIQUE** | 9.3 | tailscale_provider.dart:141 |
| 2 | VULN-003 | Module securite desactive toutes les protections | **CRITIQUE** | 8.5 | security_commands.dart:30 |
| 3 | VULN-002 | Contournement PIN par suppression SharedPrefs | **CRITIQUE** | 8.1 | lock_provider.dart:65 |
| 4 | VULN-006 | Cles Tailscale non chiffrees au repos | HAUTE | 7.5 | main.go:69 |
| 5 | VULN-009 | SSH forwarding sans filtrage | HAUTE | 7.5 | main.go:181 |
| 6 | VULN-005 | .desktop chemin non echappe | HAUTE | 7.3 | settings_provider.dart:98 |
| 7 | VULN-007 | IPC daemon non authentifie | HAUTE | 7.1 | tailscale_provider.dart:294 |
| 8 | VULN-004 | TOCTOU scripts root /tmp | HAUTE | 7.0 | ssh_setup_provider.dart:287 |
| 9 | VULN-008 | PIN memoire non effacable | HAUTE | 6.8 | lock_provider.dart:143 |
| 10 | VULN-010 | Rate limiting client-side | HAUTE | 6.5 | lock_provider.dart:215 |

> Inventaire complet : voir **CHILLAPP-INVENTAIRE-FAILLES.md**

---

## 6. Scenarios d'Attaque (Top 5)

### ATK-001 : Supply chain daemon (CVSS 9.3)
Remplacer le binaire → execution de code au demarrage → acces Tailscale + SSH forwarding.
**Temps** : 30 min | **Profil** : Competent | **Detection** : Difficile

### ATK-002 : Bypass PIN en 5 minutes (CVSS 8.1)
Supprimer les cles dans SharedPreferences → lock desactive → acces complet a l'interface.
**Temps** : 5 min | **Profil** : Script kiddie | **Detection** : Difficile

### ATK-003 : Degradation securite OS (CVSS 8.5)
Apres bypass PIN → desactiver pare-feu, AppArmor, fail2ban → activer SMBv1, RDP.
**Temps** : 2 min | **Profil** : Script kiddie | **Detection** : Facile

### ATK-009 : SSH via noeud Tailscale compromis (CVSS 7.5)
Noeud compromis → SSH forwarding sans filtrage → acces a la machine.
**Temps** : 30 min | **Profil** : Competent | **Detection** : Moderee

### ATK-010 : Brute force PIN apres reset rate limiting (CVSS 6.5)
Modifier SharedPreferences → reset compteur → brute force illimite sur 10^8 combinaisons.
**Temps** : 24h (offline) | **Profil** : Script kiddie | **Detection** : Difficile

> Scenarios complets : voir **CHILLAPP-SCENARIOS-ATTAQUE.md**

---

## 7. Chaines d'Attaque (Top 3)

### CHAIN-001 : Du fichier texte a la compromission totale (30 min)

```
ATK-002          ATK-003           ATK-001            ATK-009
Supprimer     -> Desactiver     -> Remplacer       -> SSH forwarding
cles PIN         protections OS    daemon Tailscale    vers tailnet
  [5 min]          [2 min]          [15 min]           [5 min]
```

**Impact** : Compromission totale du systeme + acces SSH a tout le tailnet.

### CHAIN-002 : Supply chain invisible (25 min)

```
ATK-001          ATK-006          ATK-007           ATK-009
Daemon piege  -> Exfiltrer     -> Controle IPC  -> SSH forwarding
                 cles Tailscale
```

**Impact** : Le daemon fonctionne normalement pour l'utilisateur. L'attaque est invisible.

### CHAIN-003 : Agent IA autonome (<1h, <100$, 0 humain)

```
ATK-013          ATK-002         ATK-001          ATK-003          ATK-009
RE par LLM    -> Bypass PIN  -> Daemon piege  -> Disable sec  -> Exfiltration
  [10 min]       [1 min]        [10 min]         [2 min]         [5 min]
```

**Impact** : Un agent IA fait tout. Reference : GTG-1002 (80-90% autonomie, ~30 organisations ciblees).

> Chaines completes : voir **CHILLAPP-CHAINES-ATTAQUE.md**

---

## 8. Menaces IA et Supply Chain

### Menaces IA Offensives (2026)

| Menace | Impact sur ChillApp |
|--------|---------------------|
| GTG-1002 (agents IA autonomes) | Compromission totale automatisee en <1h |
| LLM-Boofuzz (fuzzing SSH par IA) | 100% des vulns de test declenchees — cible ideale sur une implementation non auditee |
| LLM-Assisted RE (Blutter + GhidrAssist) | Analyse du binaire Flutter en minutes — sans obfuscation, la logique est lisible |
| PROMPTFLUX (malware polymorphe) | Mutation horaire, indetectable par AV classiques |

### Menaces Supply Chain

| Menace | Impact sur ChillApp |
|--------|---------------------|
| Binaire Go non verifie (VULN-001) | Le vecteur supply chain le plus critique — aucune verification d'integrite |
| pub.dev sans audit auto | Les dependances Dart pourraient etre compromises (typosquatting, PubNet CVE-2025-65112) |
| google_fonts au runtime | Telechargement de polices sans certificate pinning |

---

## 9. Matrice des Risques

|  | Impact Bas | Impact Moyen | Impact Haut | Impact Critique |
|---|-----------|-------------|------------|----------------|
| **Proba Haute** | VULN-018 (WoL) | VULN-011 (clipboard) VULN-013 (RE) | VULN-010 (rate limit) | **VULN-002 (PIN)** **VULN-003 (securite)** |
| **Proba Moyenne** | VULN-016 (anti-debug) VULN-017 (legacy hash) | VULN-012 (orphelins) VULN-014 (fonts) VULN-015 (plist) | VULN-005 (.desktop) VULN-006 (cles TS) VULN-007 (IPC) VULN-008 (memoire) VULN-009 (SSH fwd) | **VULN-001 (daemon)** |
| **Proba Basse** | VULN-019 (post-quantum) | | VULN-004 (TOCTOU) | |

---

## 10. Priorisation des Corrections

| Priorite | Faille | Action | Effort |
|----------|--------|--------|--------|
| **P0 - Immediat** | VULN-001 | Ajouter verification checksum SHA-256 du binaire daemon avant execution | Moyen (1-2 jours) |
| **P0 - Immediat** | VULN-002 | Remplacer SharedPreferences par un stockage chiffre au repos (libsecret/Credential Manager/Keychain) | Moyen (2-3 jours) |
| **P0 - Immediat** | VULN-003 | Ajouter une re-authentification (PIN/mot de passe) avant chaque action de desactivation de securite | Faible (1 jour) |
| **P1 - 7 jours** | VULN-010 | Deplacer le rate limiting dans le stockage chiffre (lie a la correction de VULN-002) | Faible (inclus dans VULN-002) |
| **P1 - 7 jours** | VULN-007 | Ajouter une authentification sur l'IPC daemon (token partage ou socket Unix avec verification UID) | Moyen (1-2 jours) |
| **P1 - 7 jours** | VULN-006 | Chiffrer les cles Tailscale au repos (AES-256 avec cle derivee du mot de passe utilisateur) | Moyen (2 jours) |
| **P1 - 7 jours** | VULN-009 | Ajouter un filtrage IP / liste blanche sur le SSH forwarding dans le daemon Go | Faible (1 jour) |
| **P2 - 30 jours** | VULN-005 | Echapper le chemin dans le fichier .desktop selon la spec Desktop Entry | Faible (quelques heures) |
| **P2 - 30 jours** | VULN-015 | Echapper les caracteres XML dans le plist macOS | Faible (quelques heures) |
| **P2 - 30 jours** | VULN-004 | Utiliser des named pipes ou des fichiers dans un repertoire prive au lieu de /tmp | Moyen (1 jour) |
| **P2 - 30 jours** | VULN-008 | Documenter la limitation Dart (strings immutables). Consideration : utiliser FFI pour le zero-out en natif. | Eleve (complexe) |
| **P2 - 30 jours** | VULN-013 | Ajouter --obfuscate --split-debug-info au build de production | Faible (configuration) |
| **P3 - Backlog** | VULN-011 | Ajouter un timeout automatique sur le presse-papiers (effacement apres 30 secondes) | Faible |
| **P3 - Backlog** | VULN-012 | Implementer le kill de processus apres timeout (Process.kill() dans le handler timeout) | Faible |
| **P3 - Backlog** | VULN-014 | Embarquer les polices en local au lieu de telecharger au runtime | Faible |
| **P3 - Backlog** | VULN-016 | Ajouter une detection basique anti-debug (ptrace check) | Moyen |
| **P3 - Backlog** | VULN-017 | Forcer la migration legacy SHA-256 au prochain lancement (pas seulement au prochain PIN correct) | Faible |
| **P3 - Backlog** | VULN-018 | Documenter le risque WoL (limitation du protocole, pas de correction possible) | Minimal |
| **Non applicable** | VULN-019 | Surveiller les standards post-quantiques (ML-KEM, ML-DSA) pour migration future | Minimal |

---

## 11. Annexes

| Rapport | Description |
|---------|-------------|
| **CHILLAPP-INVENTAIRE-FAILLES.md** | Catalogue complet des 19 failles avec preuves dans le code |
| **CHILLAPP-SCENARIOS-ATTAQUE.md** | 18 scenarios d'attaque detailles avec commandes et etapes |
| **CHILLAPP-CHAINES-ATTAQUE.md** | 8 chaines multi-etapes avec diagrammes et mapping Kill Chain |
| P1-RECONNAISSANCE.md | Rapport de phase — reconnaissance et surface d'attaque |
| P2-CARTOGRAPHIE-FLUX.md | Rapport de phase — flux de donnees et secrets |
| P3-CHASSE-FAILLES.md | Rapport de phase — vulnerabilites decouvertes |
| P4-CONSTRUCTION-ATTAQUES.md | Rapport de phase — scenarios d'attaque |
| P5-CHAINES-ATTAQUE.md | Rapport de phase — chaines d'attaque |

---

**Rapport genere par** : Adversary Simulation v1.0.0
**Session** : CHILLAPP_20260218_140000
