# P4 - Construction des Attaques

## Synthese

18 scenarios d'attaque construits a partir de 19 failles. 1 faille jugee non exploitable (VULN-019, post-quantique). Les scenarios couvrent 5 profils d'attaquants (script kiddie a expert) et 5 categories d'attaque. Le scenario le plus dangereux est ATK-001 (supply chain daemon, CVSS 9.3). Le plus facile est ATK-002 (bypass PIN en 5 minutes).

## Scenarios Critiques

### ATK-001 : Remplacement du binaire daemon Tailscale (CVSS 9.3)

**Faille exploitee** : VULN-001 (binaire sans verification d'integrite)
**Profil attaquant** : Competent, acces local
**Preconditions** : Acces ecriture au repertoire du binaire + redemarrage de l'app

**Etapes** :
1. Localiser le binaire `chill-tailscale` dans le filesystem
2. Compiler un daemon malveillant (reverse shell + SSH forwarding intact)
3. Remplacer le binaire original (`cp` — aucune verification d'integrite)
4. Attendre que l'utilisateur clique "Connecter Tailscale"
5. Le daemon malveillant s'execute avec acces au reseau Tailscale + SSH forwarding

**Impact** : Execution de code au demarrage. Controle du tunnel VPN et du SSH forwarding. Acces potentiel a toutes les machines du tailnet.
**Preuve** : `tailscale_provider.dart:141` — `Process.start(daemonPath, [])` sans aucune verification.
**Detection** : Difficile — seul le hash du binaire trahit l'attaque.

---

### ATK-002 : Contournement du lock PIN (CVSS 8.1)

**Faille exploitee** : VULN-002 (SharedPreferences en texte clair)
**Profil attaquant** : Script kiddie, acces local
**Preconditions** : Acces au fichier SharedPreferences

**Etapes** :
1. Localiser le fichier SharedPreferences (JSON texte clair)
2. Supprimer les cles `pin_hash` et `pin_salt`
3. Relancer l'application — le lock est desactive

**Impact** : Acces complet a l'interface sans connaitre le PIN. 5 minutes, zero outil special.
**Preuve** : `lock_provider.dart:65` — `prefs.getString(_pinHashKey) != null` determine si le lock est actif.

---

### ATK-003 : Degradation complete de la securite OS (CVSS 8.5)

**Failles exploitees** : VULN-003 + VULN-002
**Profil attaquant** : Script kiddie, acces local + mot de passe admin
**Preconditions** : PIN contourne (ATK-002) + approbation pkexec/UAC

**Etapes** :
1. Contourner le PIN (ATK-002)
2. Naviguer vers la page Securite OS
3. Desactiver le pare-feu, AppArmor, fail2ban
4. Sur Windows : activer SMBv1 et RDP

**Impact** : Toutes les protections OS desactivees. Machine completement exposee.
**Preuve** : `security_commands.dart:30+` — methodes `disable*()` sans journal d'audit.

## Scenarios Hauts

### ATK-004 : TOCTOU sur scripts root (CVSS 7.0)

**Faille** : VULN-004 | **Profil** : Expert, acces root
Surveiller /tmp avec inotifywait → remplacer le script entre ecriture et pkexec → reverse shell root.
**Preuve** : `ssh_setup_provider.dart:287`

### ATK-005 : Injection .desktop (CVSS 7.3)

**Faille** : VULN-005 | **Profil** : Competent, acces local
Modifier le champ Exec= du fichier .desktop → execution de code au login.
**Preuve** : `settings_provider.dart:98` — `Exec=$exePath` sans echappement.

### ATK-006 : Vol des cles Tailscale WireGuard (CVSS 7.5)

**Faille** : VULN-006 | **Profil** : Competent, acces local
Copier `~/.local/share/chill-app/tailscale/` → usurper l'identite du noeud sur le tailnet.
**Preuve** : `main.go:69` — permissions 0700 seulement.

### ATK-007 : Injection IPC daemon (CVSS 7.1)

**Faille** : VULN-007 | **Profil** : Competent, acces local
Envoyer des commandes JSON sur le stdin du daemon → login/logout/shutdown.
**Preuve** : `tailscale_provider.dart:294` — JSON en clair, pas d'authentification.

### ATK-008 : Extraction PIN par dump memoire (CVSS 6.8)

**Faille** : VULN-008 | **Profil** : Competent, acces root
Dump memoire avec gcore → chercher les strings numeriques → PIN en clair.
**Preuve** : `lock_provider.dart:143` — String Dart immutable.

### ATK-009 : SSH via noeud Tailscale compromis (CVSS 7.5)

**Faille** : VULN-009 | **Profil** : Competent, acces reseau tailnet
Depuis un noeud compromis → connexion SSH via le forwarding sans filtrage.
**Preuve** : `main.go:181` — aucun filtrage ni rate limiting.

### ATK-010 : Brute force PIN apres reset rate limiting (CVSS 6.5)

**Failles** : VULN-010 + VULN-002 | **Profil** : Script kiddie, acces local
Reset `pin_failed_attempts` dans SharedPreferences → brute force illimite.
**Preuve** : `lock_provider.dart:215` — compteur dans fichier texte.

## Scenarios Moyens

| ID | Titre | CVSS | Technique |
|----|-------|------|-----------|
| ATK-011 | Surveillance clipboard | 4.3 | Monitor presse-papiers → exfiltrer IP/MAC/hostname |
| ATK-012 | Processus orphelins root | 5.3 | Timeout repete → accumulation pkexec orphelins |
| ATK-013 | Reverse engineering | 4.0 | Blutter + GhidrAssist → comprendre toute la logique securite |
| ATK-014 | MITM google_fonts | 4.8 | Police malformee → potentiel CVE-2025-27363 FreeType RCE |
| ATK-015 | Injection plist macOS | 5.5 | Modifier le plist → execution au login macOS |

## Scenarios Bas (utiles dans les chaines)

| ID | Titre | CVSS | Technique |
|----|-------|------|-----------|
| ATK-016 | Frida bypass PIN | 3.1 | Hooker verifyPin → toujours retourner true |
| ATK-017 | Craquage hash legacy | 3.7 | SHA-256 sans sel → hashcat en secondes |
| ATK-018 | WoL non authentifie | 3.1 | Magic packet → reveiller la machine pour attaquer |

## Faille Non Exploitable

| VULN | Raison |
|------|--------|
| VULN-019 (post-quantique) | Les ordinateurs quantiques cryptographiquement pertinents n'existent pas encore. Impact theorique a horizon >2035. |

## Couverture

```
P3.summary.total = 19
P4.mapped_to_scenario = 18
P4.not_exploitable = 1
INVARIANT : 18 + 1 = 19 ✓
```

## Observations de l'Attaquant

### Scenarios les plus rentables (effort vs impact)

1. **ATK-002** (bypass PIN) : 5 minutes, script kiddie, ouvre la porte a ATK-003 (degradation securite)
2. **ATK-001** (supply chain daemon) : 30 minutes, competent, impact maximal (CVSS 9.3)
3. **ATK-010** (brute force PIN) : entierement scriptable, aucune interaction

### Scenarios automatisables

- **ATK-002 + ATK-003** : Script Python qui supprime le hash PIN puis un macro qui desactive les protections
- **ATK-010** : Script brute force avec reset automatique du rate limiting
- **ATK-001** : Automatisable via un malware qui remplace le binaire

### Scenarios necessitant de l'ingenierie sociale

- **ATK-003** : Necessitent l'approbation pkexec/UAC (sauf si l'attaquant connait le mot de passe admin)
- **ATK-018** : Plus utile combine avec un pretexte pour justifier le reveil de la machine

### Verdict de l'attaquant

> La combinaison ATK-002 (bypass PIN en 5 min) → ATK-003 (desactiver les protections) → ATK-001 (supply chain daemon) constitue le chemin d'attaque le plus devastateur. Un attaquant methodique commence par le PIN, ouvre les defenses, puis installe le daemon malveillant pour un acces permanent via Tailscale.
