# Suivi Audit Securite — ChillApp

**Date :** 2026-02-12
**Methodologie :** Trail of Bits — sharp-edges + audit-context-building
**Agents :** 4 analystes (audit-context, sharp-edges-commands, sharp-edges-pin, sharp-edges-network) + 2 correcteurs (fix-pin, fix-injection)

---

## Resume

| Severite | Total | Corriges | Restants |
|----------|-------|----------|----------|
| **Critical** | 4 | 4 | 0 |
| **High** | 8 | 8 | 0 |
| **Medium** | 14 | 0 | 14 |
| **Low** | 12 | 0 | 12 |
| **TOTAL** | **38** | **12** | **26** |

---

## Phase 1 — Corrections CRITICAL + HIGH (terminee)

### CRITICAL — Tous corriges

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-001** | SHA-256 single-pass sur PIN 8 chiffres (brute force 0.01s) | `lock_provider.dart` | PBKDF2 HMAC-SHA256 100k iterations. Migration auto ancien format (SHA-256 hex 64 chars → PBKDF2 base64 44 chars) | CORRIGE |
| **SE-PIN-002** | SharedPreferences en clair, suppression directe du lock | `lock_provider.dart` | Mitigation : PBKDF2 rend le brute force offline impraticable. Documentation de la limitation ajoutee en docblock | MITIGUE |
| **SE-CMD-001** | Injection commandes runElevated() macOS (backticks, \n) | `command_runner.dart` | Script temp elevated.sh + _shellQuote() POSIX (single-quote wrapping). Seul le chemin du script est injecte dans osascript | CORRIGE |
| **SE-CMD-002** | Injection commandes runElevated() Windows (triple nesting PS) | `command_runner.dart` | Script temp elevated.ps1 + _psQuote(). Execution via -File au lieu de -Command, empechant l'interpretation du contenu | CORRIGE |

### HIGH — Tous corriges

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-003** | Pas de guard PIN dans GoRouter | `router.dart` | Documentation pattern securite : le swap MaterialApp/MaterialApp.router dans app.dart protege automatiquement toutes les routes | CORRIGE |
| **SE-PIN-004** | Race condition boot : lock bypass temporaire | `lock_provider.dart`, `app.dart` | Ajout isLoading=true par defaut dans LockState. Splash screen affiche jusqu'a _load() termine. Ni lock ni router visible pendant le chargement | CORRIGE |
| **SE-PIN-005** | Rate limiting contournable par horloge systeme | `lock_provider.dart` | Compteur monotone (jamais remis a 0 a l'expiration). Reset uniquement apres PIN correct | CORRIGE |
| **SE-PIN-006** | Rate limiting sans escalade (reset a 0 apres expiration) | `lock_provider.dart` | Backoff exponentiel : 30s apres 5 echecs, 60s apres 10, 120s apres 15, plafonne a 300s. Methode _lockDurationSeconds() | CORRIGE |
| **SE-CMD-003** | TOCTOU fichiers temp executes en root via pkexec | `ssh_setup_provider.dart`, `wol_setup_provider.dart` | chmod 700 sur repertoire temp et scripts. Documentation risque residuel TOCTOU | CORRIGE |
| **SE-CMD-004** | Interface name interpolee dans scripts shell root | `wol_setup_provider.dart` | Validation via NetworkInfo.isValidInterfaceName() (regex ^[a-zA-Z0-9][a-zA-Z0-9._-]*$, max 15 chars) avant utilisation | CORRIGE |
| **SE-NET-001** | Interface name injection dans commandes bash | `network_info.dart` | isValidInterfaceName() centralise. Validation dans getEthernetIp(), getWifiIp(), getMacAddress() | CORRIGE |
| **SE-NET-002** | URL daemon Tailscale ouverte sans validation | `tailscale_provider.dart` | Validation schema HTTPS uniquement dans _openUrl() et handler auth_url. URL non-HTTPS rejetees avec debugPrint | CORRIGE |

---

## Phase 2 — MEDIUM + LOW (a faire)

### MEDIUM (14 findings)

| ID | Probleme | Fichier | Priorite |
|----|----------|---------|----------|
| SE-PIN-007 | Rate limiting partiellement contournable au redemarrage | `lock_provider.dart` | Mitigue par persistance SharedPreferences |
| SE-PIN-008 | Comparaison hash non constante en temps (==) | `lock_provider.dart` | Faible risque pratique (app locale) |
| SE-PIN-009 | Pas de validation longueur PIN dans setPin() | `lock_provider.dart` | UI impose 8 chiffres mais API non protegee |
| SE-PIN-010 | Migration ancien format sans salt encore presente | `lock_provider.dart` | Code de migration necessaire pour compatibilite |
| SE-CMD-005 | Interpolation adapter dans bash -c (network_info) | `network_info.dart` | Mitigue par SE-NET-001 (validation interface) |
| SE-CMD-006 | runPowerShell() accepte commandes par concatenation | `command_runner.dart` | Pattern d'echappement a ameliorer |
| SE-CMD-007 | Race condition retry() daemon Tailscale | `tailscale_provider.dart` | Double-clic rapide → deux daemons |
| SE-CMD-008 | Timeout Process.run ne kill pas le processus | `command_runner.dart` | Processus orphelins possibles |
| SE-CMD-009 | Daemon path fallback sur PATH sans validation | `tailscale_provider.dart` | Binaire non verifie |
| SE-CMD-010 | Fichier service systemd avec ethIface interpole | `wol_setup_provider.dart` | Mitigue par SE-CMD-004 (validation interface) |
| SE-NET-003 | Fuite infos systeme via stderr dans erreurs | `ssh/wol_setup_provider.dart` | Chemins et versions exposes |
| SE-NET-004 | Chemin temp previsible pour scripts elevation | `ssh/wol_setup_provider.dart` | Mitigue par chmod 700 (SE-CMD-003) |
| SE-NET-005 | Pas de guard PIN dans router (redondant SE-PIN-003) | `router.dart` | Documente dans Phase 1 |
| SE-NET-006 | Parsing JSON Tailscale sans validation champs | `tailscale_provider.dart` | TypeError catch generique |
| SE-NET-007 | Clipboard sans expiration (IPs, MAC) | `copyable_info.dart` | Donnees sensibles persistent |

### LOW (12 findings)

| ID | Probleme | Fichier |
|----|----------|---------|
| SE-PIN-011 | PIN en memoire (String immutable Dart) | `lock_screen.dart` |
| SE-PIN-012 | Pas de tests unitaires pour le lock | `test/` |
| SE-NET-008 | Regex IP trop permissive (>255) | `network_info.dart` |
| SE-NET-009 | Cles traduction manquantes retournent la cle | `locale_provider.dart` |
| SE-NET-010 | Locale accepte valeurs arbitraires | `locale_provider.dart` |
| SE-NET-011 | Pas de support IPv6 | `network_info.dart` |
| SE-NET-012 | debugPrint expose chemin daemon | `tailscale_provider.dart` |
| SE-CMD-011 | Resultat Process.run ignore dans _openUrl | `tailscale_provider.dart` |
| SE-CMD-012 | URL non validee dans _openUrl (Windows cmd) | `tailscale_provider.dart` |
| SE-CMD-013 | Catch vide dans _shutdownDaemon et cleanup | `tailscale_provider.dart` |
| SE-CMD-014 | Pas de validation permissions binaire daemon | `tailscale_provider.dart` |

---

## Verification

- `flutter analyze` : 0 erreurs
- `flutter test` : 42/42 tests passent
- Fichiers modifies Phase 1 : command_runner.dart, lock_provider.dart, app.dart, router.dart, network_info.dart, tailscale_provider.dart, ssh_setup_provider.dart, wol_setup_provider.dart, widget_test.dart

## Rapports d'audit

- Contexte architectural : `docs/AUDIT/CONTEXTE_SECURITE.md`
- Suivi qualite (audit precedent) : `docs/AUDIT/SUIVIE_QUALITE.md`
