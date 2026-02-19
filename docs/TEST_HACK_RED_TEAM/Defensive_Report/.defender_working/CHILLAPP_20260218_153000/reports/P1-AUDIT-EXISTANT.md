# P1 — Audit de l'Existant

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Stack** : Flutter 3.38.7 / Dart 3.10.7 + Daemon Go (chill-tailscale)

---

## Synthese

**13 protections trouvees. Posture globale : FAIBLE (8.6% de couverture).**

L'application possede une cryptographie PIN correcte (PBKDF2, temps constant) et un echappement shell solide, mais manque cruellement de protections dans toutes les autres categories : pas de stockage securise, pas d'anti-reverse engineering, pas de protection reseau, pas de defense active, pas de detection comportementale.

---

## Protections Existantes

| ID | Cat. | Protection | Fichier | Efficacite |
|----|------|-----------|---------|------------|
| PROT-001 | RT | Random.secure() pour sel crypto | lock_provider.dart:80 | Forte |
| PROT-002 | RT | PBKDF2-HMAC-SHA256, 100k iterations | lock_provider.dart:86 | Forte |
| PROT-003 | RT | Comparaison temps constant (XOR) | lock_provider.dart:120 | Forte |
| PROT-004 | RT | Validation PIN (regex 8 chiffres) | lock_provider.dart:144 | Forte |
| PROT-005 | RT | Migration hash legacy → PBKDF2 | lock_provider.dart:169 | Partielle |
| PROT-006 | RT | Limitation SE-PIN-011 documentee | lock_provider.dart:14 | Faible |
| PROT-007 | FW | Auto-effacement presse-papiers (3s) | copyable_info.dart:33 | Partielle |
| PROT-008 | FW | Rate limiting PIN (backoff expo.) | lock_provider.dart:134 | Faible |
| PROT-009 | OS | Echappement shell POSIX/PowerShell | command_runner.dart:69 | Forte |
| PROT-010 | OS | Nettoyage temp dirs (finally) | command_runner.dart:101 | Partielle |
| PROT-011 | OS | chmod 700 scripts avant pkexec | ssh_setup_provider.dart:293 | Partielle |
| PROT-012 | OS | Permissions 0700 dir Tailscale | main.go:69 | Partielle |
| PROT-013 | OS | Module securite OS (check/toggle) | security_commands.dart | Partielle |

---

## Posture par Categorie

```
RT (Runtime Dart)      : ████████░░  5/10  — Crypto correcte, mais pas d'isolates ni de memoire securisee
FW (Framework Flutter) : ██░░░░░░░░  2/10  — Clipboard auto-clear, rate limiting client-side faible
SC (Stockage/Crypto)   : █░░░░░░░░░  1/10  — SharedPreferences en texte clair, pas de keystore
NW (Reseau)            : ░░░░░░░░░░  0/10  — Aucune protection reseau
OS (Systeme)           : ████░░░░░░  4/10  — Bon echappement, permissions OK, module securite
AR (Anti-Reverse)      : ░░░░░░░░░░  0/10  — Aucune obfuscation, RASP, anti-debug
DC (Deception)         : ░░░░░░░░░░  0/10  — Aucun honeypot, canary, kill switch
BH (Comportemental)    : ░░░░░░░░░░  0/10  — Aucune detection IA, analyse comportementale
```

---

## Forces

1. **Cryptographie PIN solide** : PBKDF2-HMAC-SHA256 avec 100 000 iterations, sel Random.secure(), comparaison en temps constant. C'est du travail correct.
2. **Echappement shell** : Les fonctions `_shellQuote()` et `_psQuote()` dans CommandRunner previennent les injections de commandes. Les arguments ne sont pas interpoles directement dans les commandes.
3. **Nettoyage du presse-papiers** : L'auto-effacement apres 3 secondes est une bonne pratique.
4. **Documentation** : Les limitations connues sont documentees dans le code (SE-PIN-011, note sur timeout/processus orphelins).

---

## Faiblesses

### Critiques (impact immediat)

1. **SharedPreferences en texte clair** : Le hash PIN, le sel, le rate limiting — tout est dans un fichier JSON lisible par tout processus. Supprimer les cles = desactiver le lock.
2. **Daemon sans verification d'integrite** : Le binaire chill-tailscale (~33Mo) est execute avec `Process.start()` sans aucun checksum, hash ou signature.
3. **IPC non authentifie** : La communication daemon/app se fait en JSON clair sur stdin/stdout. Aucune authentification.
4. **Module securite bipolaire** : Permet de desactiver pare-feu, AppArmor, fail2ban en quelques clics. Pas de journal d'audit.

### Hautes (exploitable avec effort modere)

5. **Fenetre TOCTOU** : Scripts temporaires ecrits dans /tmp puis executes via pkexec. La fenetre entre ecriture et execution est exploitable.
6. **SSH forwarding ouvert** : Le daemon forwarde toute connexion port 22 Tailscale vers localhost sans filtrage.
7. **PIN en memoire** : String Dart immutable, non effacable. Dump memoire = extraction du PIN.
8. **Pas d'obfuscation** : Binaire Flutter non obfusque, noms en clair. RE trivial avec Blutter.

### Moyennes a basses (preparation)

9. **google_fonts sans pinning** : Telechargement au runtime sans certificate pinning. Vecteur MITM.
10. **Processus orphelins** : timeout ne tue pas les processus pkexec.

---

## Categories Non Couvertes (score 0/10)

| Categorie | Ce qui manque completement |
|-----------|---------------------------|
| **NW** (Reseau) | Certificate pinning, heartbeat, fail closed, mTLS, proxy detection, filtrage SSH |
| **AR** (Anti-Reverse) | Obfuscation, freeRASP, anti-debug, anti-Frida, integrite binaire, signature code |
| **DC** (Deception) | Honeypots, canary tokens, tarpits, kill switch, secure logging, plausible deniability |
| **BH** (Comportemental) | Detection agents IA, analyse comportementale, rate limiting anti-IA, ML on-device |

---

## Couverture des Bases de Connaissances

| Base de connaissances | Sections | Couvertes | Pourcentage |
|-----------------------|----------|-----------|-------------|
| dart-runtime-hardening.md | 18 | 3 | 17% |
| flutter-framework-hardening.md | 19 | 2 | 11% |
| storage-crypto-hardening.md | 6 | 0 | 0% |
| network-hardening.md | 15 | 0 | 0% |
| os-hardening.md | 11 | 4 | 36% |
| anti-reverse-engineering.md | 12 | 0 | 0% |
| deception-monitoring.md | 14 | 0 | 0% |
| ai-defense-strategies.md | 10 | 0 | 0% |
| **Total** | **105** | **9** | **8.6%** |

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
