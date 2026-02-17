# 🔓 Red Team Security Audit — Chill Desktop

## ⚡ ÉTAPE 0 — ACTIVATION DU SKILL RED TEAM (OBLIGATOIRE)

**AVANT de commencer toute analyse, tu DOIS invoquer le skill red-team** :

**Instruction pour Claude** :
1. **Utilise immédiatement** le Skill tool avec `skill: "red-team"`
2. Attends que le skill soit chargé et lis ses instructions
3. Applique la méthodologie Red Team Analysis du skill pour l'audit

**Si le skill n'est pas disponible** : Utilise l'approche Red Team manuelle avec MITRE ATT&CK décrite ci-dessous.

---

## 🎯 Contexte de la Mission

Tu es un **pentester senior et red teamer** avec 15 ans d'expérience en sécurité offensive. Tu viens d'être engagé pour tester la sécurité de **Chill Desktop** AVANT sa mise en production. Ton objectif est de penser comme un attaquant réel — pas comme un auditeur qui coche des cases.

**MÉTHODOLOGIE** : Red Team Analysis + MITRE ATT&CK Framework

---

## 📋 Informations Système

**Application** : Chill Desktop
- **Type** : Application desktop Electron (Windows/macOS/Linux)
- **Fonction** : Interface GUI pour contrôler Tailscale (VPN mesh networking)
- **Stack technique** : Flutter Desktop, Go daemon (tailscale-daemon), IPC
- **Codebase** : 8.6k LOC
- **Autorisation** : Test autorisé par le propriétaire (white-box testing)

---

## 🔍 Contexte Sécurité Préexistant

**Scans automatisés déjà effectués** :
- ✅ **Semgrep** : 0 vulnérabilités détectées
- ✅ **Flutter Analyze** : Warnings info (deprecated APIs, pas de bugs)
- ✅ **SonarCloud** : Security Rating D (1 Blocker), 93 issues maintenabilité

**Problèmes critiques connus** :
- 🔴 **SEC-001 (BLOCKER)** : Utilisation de `/tmp` prédictible pour création de répertoires Tailscale
  - Fichier : `tailscale-daemon/main.go` ligne 80-83
  - Risque : Symlink attack, directory traversal
  - Status : **NON CORRIGÉ** (à valider pendant l'audit)

**Fichiers de référence** :
- `docs/PREPARATION_GITHUB/VULNERABILITES_TROUVEES.md` : Tous les findings SonarCloud
- `docs/PREPARATION_GITHUB/CORRECTIONS_SECURITE.md` : Plan de correction (non appliqué)

---

## 🚀 PHASE 1 — RECONNAISSANCE (ne touche à rien, observe)

Analyse la codebase complète (`lib/` + `tailscale-daemon/`) et produis :

### 1.1 Cartographie de la Surface d'Attaque
Liste TOUS les points d'entrée :
- Inputs utilisateur (GUI Flutter)
- IPC entre Flutter et Go daemon (quel mécanisme ?)
- Daemon Go (ports réseau, fichiers, permissions)
- Tailscale CLI wrapper (commandes exécutées)
- Stockage local (config Tailscale, credentials)
- Permissions système (admin/sudo requis ?)

### 1.2 Flux de Données Sensibles
Trace le parcours des données critiques :
- **Auth tokens Tailscale** : obtention → stockage → rotation
- **Tailscale state** : machine key, node key, prefs
- **IPC messages** : validation, sanitization, encryption ?
- **Commandes système** : comment sont construites et exécutées ?

### 1.3 Inventaire des Dépendances
Identifie packages critiques :
- **Go** : `tailscale.com/` packages, version, CVE connues
- **Flutter** : packages IPC, système, réseau
- **Daemon** : bibliothèques système (cgo ?)

### 1.4 Trust Boundaries
Identifie où le code fait confiance à des données externes :
- Réponses Tailscale API (coordination server)
- Output des commandes `tailscale` CLI
- Fichiers de configuration modifiables par user
- Messages IPC depuis Flutter GUI

---

## ⚔️ PHASE 2 — SCÉNARIOS D'ATTAQUE (pense comme un vrai attaquant)

Pour chaque vecteur identifié, utilise **MITRE ATT&CK Enterprise** :

| Technique | Qui | Comment | Impact | Difficulté |
|-----------|-----|---------|--------|------------|
| T1068 (Exploitation for Privilege Escalation) | User local | Exploit /tmp race condition | Elevation vers root | Modéré |
| T1574.006 (Hijack Execution Flow: Dynamic Linker) | Malware | LD_PRELOAD injection dans daemon | Contrôle daemon | Avancé |
| T1557.001 (Man-in-the-Middle: LLMNR/NBT-NS Poisoning) | Attaquant réseau | Intercept Tailscale coordination | MITM VPN traffic | Avancé |
| T1555 (Credentials from Password Stores) | Malware | Vol des credentials Tailscale | Accès au mesh network | Modéré |

**Priorise les scénarios qui mènent à un impact RÉEL**, pas les vulnérabilités théoriques.

---

## 🎯 PHASE 3 — ATTAQUES PRIORITAIRES

### a) Vulnérabilité `/tmp` Connue (SEC-001)

**Analyse approfondie requise** :
```go
// tailscale-daemon/main.go L80-83
default:
    dir := filepath.Join(os.TempDir(), "chill-app-tailscale")
    os.MkdirAll(dir, 0700)
    return dir
```

**Questions clés** :
1. Ce code est-il **toujours exécuté** ? (quelle condition déclenche `default:` ?)
2. L'attaque **TOCTOU (Time-of-Check-Time-of-Use)** est-elle possible ?
   ```bash
   # Attaquant crée un symlink avant le daemon
   ln -s /etc/passwd /tmp/chill-app-tailscale
   # Daemon écrit dedans et écrase /etc/passwd
   ```
3. Les **permissions 0700** sont-elles suffisantes ?
4. Y a-t-il d'autres **fichiers créés** dans ce répertoire ?
5. Le répertoire est-il **nettoyé** à la fin ?

**Remédiation recommandée** :
```go
import "os"

dir, err := os.MkdirTemp("", "chill-app-tailscale-*")
if err != nil {
    return "", fmt.Errorf("failed to create temp dir: %w", err)
}
// Plus de race condition, nom aléatoire, 0700 par défaut
return dir, nil
```

**Impact réel à démontrer** :
- Proof-of-concept d'exploitation
- Quelle élévation de privilèges exactement ?
- Dépend-il de conditions système spécifiques ?

### b) Sécurité du Daemon Go

**Questions clés** :
- Le daemon tourne-t-il avec **privilèges élevés** ?
  - Pourquoi a-t-il besoin de root/admin ?
  - Peut-on le faire tourner en user normal ?
- Comment l'**IPC Flutter ↔ Go** est-elle sécurisée ?
  - Quel mécanisme (Unix socket, TCP, named pipes) ?
  - Authentification ? Chiffrement ?
  - Peut-on injecter des commandes malveillantes ?
- Le daemon expose-t-il un **port réseau** ?
  - Écoute sur `127.0.0.1` uniquement ?
  - Authentification requise ?
- Les **commandes Tailscale** sont-elles sanitizées ?
  - Injection de commandes via arguments ?
  - Path traversal dans les paths ?

### c) Sécurité des Credentials Tailscale

**Questions clés** :
- Où sont stockés les **tokens Tailscale** ?
  - Keychain macOS / Credential Manager Windows / Secret Service Linux ?
  - Fichiers en clair ?
- Un attaquant local peut-il les **extraire** ?
  - Permissions fichiers ?
  - Accessible sans sudo ?
- Les credentials transitent-elles en **clair en mémoire** ?
  - Logs debug ?
  - Core dumps ?

### d) Injection et Manipulation d'Input

**Questions clés** :
- Peut-on injecter des **commandes système** ?
  - Via la GUI Flutter ?
  - Via l'IPC vers le daemon ?
- Les **paths** sont-ils sanitizés ?
  - Path traversal dans config files ?
- Les **hostnames Tailscale** sont-ils validés ?
  - DNS rebinding attacks ?

### e) Logique Applicative

**Questions clés** :
- Y a-t-il des **race conditions** ?
  - Daemon start/stop concurrency issues ?
- La **gestion des erreurs** révèle-t-elle des infos ?
  - Stack traces Go avec internal paths ?
  - Messages d'erreur Tailscale trop verbeux ?
- Les **timeouts** sont-ils sécurisés ?
  - Daemon zombie processes ?

### f) Supply Chain et Build

**Questions clés** :
- Les **dépendances Go** sont-elles épinglées ?
  - `go.mod` avec versions exactes ?
  - Packages abandonnés ou avec CVEs ?
- Le **build process** expose-t-il des secrets ?
  - Secrets in build scripts ?
- Y a-t-il des **permissions excessives** ?
  - Daemon tournant en root ?
  - Capabilities Linux trop larges ?

---

## 📊 PHASE 4 — RAPPORT OFFENSIF

Produis un rapport structuré avec **UNIQUEMENT des findings concrets** (pas de théorie) :

| Champ | Détail |
|-------|--------|
| 🎯 **Titre** | Nom clair de la vulnérabilité |
| 💀 **Sévérité** | CRITIQUE / HAUTE / MOYENNE / BASSE |
| 🏷️ **MITRE ATT&CK** | Technique ID (ex: T1068) |
| 🗡️ **Scénario d'attaque** | Comment un attaquant exploite concrètement |
| 💥 **Impact** | Ce que l'attaquant obtient (root, vol credentials, etc.) |
| 📍 **Localisation** | Fichier(s) exact(s) et ligne(s) concernés |
| 🛡️ **Remédiation** | Fix recommandé avec exemple de code Go/Dart si possible |
| ⏱️ **Effort de fix** | Rapide (<1h) / Modéré (quelques heures) / Complexe (refactor) |

**Classe les findings par sévérité décroissante.**

---

## 🌐 PHASE 5 — VISION GLOBALE

Termine par :

### 1. Score de Sécurité Global
Note sur 10 avec justification détaillée

### 2. Top 3 des Risques
Les 3 choses à corriger en **PRIORITÉ ABSOLUE** avant publication

### 3. Points Positifs
Ce qui est **BIEN fait** (important aussi !)

### 4. Recommandations Architecturales
Changements structurels si nécessaire

### 5. Quick Wins
Les fixes **rapides à fort impact** (<2h de dev)

---

## 📁 LIVRABLES

**Rapport complet** à sauvegarder dans :
```
docs/TEST_HACK_RED_TEAM/RAPPORT_RED_TEAM_CHILL.md
```

**Format requis** :
- Markdown avec tables
- Code examples en Go/Dart
- PoC d'exploitation si possible
- Liens vers MITRE ATT&CK techniques

---

## ⚠️ RÈGLES CRITIQUES

1. **Sois brutalement honnête mais constructif**
   - Si c'est cassé, dis-le clairement
   - Propose toujours une solution

2. **Pas de jargon inutile**
   - Explique comme si tu briefais un dev qui n'est pas spécialiste sécu

3. **Exemples de code concrets**
   - Donne des snippets Go/Dart pour les remédiations

4. **Ne spécule pas**
   - Si tu n'es pas sûr d'un finding, dis-le clairement
   - Teste mentalement l'exploit avant de l'affirmer

5. **Pointe vers du code RÉEL**
   - Chaque finding doit référencer des fichiers/lignes précis dans ce projet
   - Ne liste PAS des vulnérabilités génériques

6. **Focus sur SEC-001**
   - La vulnérabilité `/tmp` est **confirmée par SonarCloud**
   - Démontre son exploitabilité RÉELLE avec un PoC si possible

---

## 🚦 CHECK-LIST DE LANCEMENT

Avant de commencer l'audit, vérifie :
- [ ] Skill `red-team` activé
- [ ] Documentation sécurité lue (`VULNERABILITES_TROUVEES.md`, `CORRECTIONS_SECURITE.md`)
- [ ] Codebase explorée (`lib/` + `tailscale-daemon/`)
- [ ] `tailscale-daemon/main.go` L80-83 analysé en détail
- [ ] MITRE ATT&CK Enterprise reference accessible

---

**COMMENCE L'AUDIT RED TEAM MAINTENANT. Réponds en français.**
