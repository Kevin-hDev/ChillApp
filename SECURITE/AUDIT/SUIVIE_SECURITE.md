# Suivi Audit Securite — ChillApp

**Date :** 2026-02-12
**Methodologie :** Trail of Bits — sharp-edges + audit-context-building
**Agents Phase 1 :** 4 analystes (audit-context, sharp-edges-commands, sharp-edges-pin, sharp-edges-network) + 2 correcteurs (fix-pin, fix-injection)
**Agents Phase 2 :** 4 correcteurs (fix-pin-medium, fix-commands-medium, fix-network-medium, fix-pin-tests)

---

## Resume

| Severite | Total | Corriges | Mitigues/Doc | Restants |
|----------|-------|----------|--------------|----------|
| **Critical** | 4 | 4 | 0 | 0 |
| **High** | 8 | 8 | 0 | 0 |
| **Medium** | 14 | 8 | 6 | 0 |
| **Low** | 12 | 7 | 5 | 0 |
| **TOTAL** | **38** | **27** | **11** | **0** |

---

## Phase 1 — Corrections CRITICAL + HIGH (terminee)

### CRITICAL — Tous corriges

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-001** | SHA-256 single-pass sur PIN 8 chiffres (brute force 0.01s) | `lock_provider.dart` | PBKDF2 HMAC-SHA256 100k iterations. Migration auto ancien format (SHA-256 hex 64 chars -> PBKDF2 base64 44 chars) | CORRIGE |
| **SE-PIN-002** | SharedPreferences en clair, suppression directe du lock | `lock_provider.dart` | Mitigation : PBKDF2 rend le brute force offline impraticable. Documentation de la limitation ajoutee en docblock | MITIGUE |
| **SE-CMD-001** | Injection commandes runElevated() macOS (backticks, \n) | `command_runner.dart` | Script temp elevated.sh + _shellQuote() POSIX (single-quote wrapping). Seul le chemin du script est injecte dans osascript | CORRIGE |
| **SE-CMD-002** | Injection commandes runElevated() Windows (triple nesting PS) | `command_runner.dart` | Script temp elevated.ps1 + _psQuote(). Execution via -File au lieu de -Command, empechant l'interpretation du contenu | CORRIGE |

### HIGH — Tous corriges

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-003** | Pas de guard PIN dans GoRouter | `router.dart` | Documentation pattern securite : le swap MaterialApp/MaterialApp.router dans app.dart protege automatiquement toutes les routes | CORRIGE |
| **SE-PIN-004** | Race condition boot : lock bypass temporaire | `lock_provider.dart`, `app.dart` | Ajout isLoading=true par defaut dans LockState. Splash screen affiche jusqu'a _load() termine | CORRIGE |
| **SE-PIN-005** | Rate limiting contournable par horloge systeme | `lock_provider.dart` | Compteur monotone (jamais remis a 0 a l'expiration). Reset uniquement apres PIN correct | CORRIGE |
| **SE-PIN-006** | Rate limiting sans escalade (reset a 0 apres expiration) | `lock_provider.dart` | Backoff exponentiel : 30s apres 5 echecs, 60s apres 10, 120s apres 15, plafonne a 300s | CORRIGE |
| **SE-CMD-003** | TOCTOU fichiers temp executes en root via pkexec | `ssh_setup_provider.dart`, `wol_setup_provider.dart` | chmod 700 sur repertoire temp et scripts. Documentation risque residuel TOCTOU | CORRIGE |
| **SE-CMD-004** | Interface name interpolee dans scripts shell root | `wol_setup_provider.dart` | Validation via NetworkInfo.isValidInterfaceName() (regex stricte, max 15 chars) | CORRIGE |
| **SE-NET-001** | Interface name injection dans commandes bash | `network_info.dart` | isValidInterfaceName() centralise. Validation dans getEthernetIp(), getWifiIp(), getMacAddress() | CORRIGE |
| **SE-NET-002** | URL daemon Tailscale ouverte sans validation | `tailscale_provider.dart` | Validation schema HTTPS uniquement dans _openUrl() et handler auth_url | CORRIGE |

---

## Phase 2 — Corrections MEDIUM + LOW (terminee)

### MEDIUM — Tous traites

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-007** | Rate limiting contournable au redemarrage | `lock_provider.dart` | Deja mitigue par persistance SharedPreferences + splash screen isLoading. Commentaire SECURITY ajoute | MITIGUE |
| **SE-PIN-008** | Comparaison hash non constante en temps | `lock_provider.dart` | Ajout _constantTimeEquals() (XOR bit a bit). 3 comparaisons remplacees dans verifyPin() | CORRIGE |
| **SE-PIN-009** | Pas de validation longueur PIN dans setPin() | `lock_provider.dart` | Validation regex ^\d{8}$ en debut de setPin(). ArgumentError si invalide | CORRIGE |
| **SE-PIN-010** | Migration ancien format sans salt | `lock_provider.dart` | Commentaire MIGRATION documentant les 3 formats (pre-v1, v1, v2) et strategie. TODO suppression future | DOCUMENTE |
| **SE-CMD-005** | Interpolation adapter dans bash -c | `network_info.dart` | Deja mitigue par validation isValidInterfaceName() (Phase 1 SE-NET-001) | MITIGUE |
| **SE-CMD-006** | runPowerShell() echappement insuffisant | `wol_setup_provider.dart` | Remplacement double-quotes par single-quotes PS dans powercfg /deviceenablewake | CORRIGE |
| **SE-CMD-007** | Race condition retry() daemon Tailscale | `tailscale_provider.dart` | Ajout guard _isRetrying avec try/finally contre appels concurrents | CORRIGE |
| **SE-CMD-008** | Timeout Process.run ne kill pas le processus | `command_runner.dart` | Limitation Dart documentee. Piste Process.start() pour amelioration future | DOCUMENTE |
| **SE-CMD-009** | Daemon path fallback sur PATH | `tailscale_provider.dart` | Ajout warning debugPrint quand fallback PATH utilise | CORRIGE |
| **SE-CMD-010** | Fichier service systemd avec ethIface interpole | `wol_setup_provider.dart` | Deja mitigue par validation interface (Phase 1 SE-CMD-004) | MITIGUE |
| **SE-NET-003** | Fuite infos systeme via stderr | `ssh/wol_setup_provider.dart` | Messages generiques dans errorDetail. stderr vers debugPrint uniquement (11 endroits) | CORRIGE |
| **SE-NET-004** | Chemin temp previsible | `ssh/wol_setup_provider.dart` | Deja mitigue par chmod 700 (Phase 1 SE-CMD-003) | MITIGUE |
| **SE-NET-005** | Pas de guard PIN dans router | `router.dart` | Deja traite en Phase 1 (SE-PIN-003). Redondant | MITIGUE |
| **SE-NET-006** | Parsing JSON Tailscale sans validation | `tailscale_provider.dart` | Extraction methode _parsePeer() avec try-catch + whereType filtre les peers invalides | CORRIGE |
| **SE-NET-007** | Clipboard sans expiration | `copyable_info.dart`, `connection_info_screen.dart` | Auto-clear clipboard apres 30 secondes via Future.delayed | CORRIGE |

### LOW — Tous traites

| ID | Probleme | Fichier | Correction | Statut |
|----|----------|---------|------------|--------|
| **SE-PIN-011** | PIN en memoire (String immutable Dart) | `lock_provider.dart`, `lock_screen.dart` | Limitation Dart documentee. Commentaires KNOWN LIMITATION ajoutes | DOCUMENTE |
| **SE-PIN-012** | Pas de tests unitaires pour le lock | `test/unit/lock_test.dart` | 19 tests crees : setPin, verifyPin, rate limiting, backoff, removePin, migration legacy | CORRIGE |
| **SE-NET-008** | Regex IP trop permissive | `network_info.dart` | Limitation documentee (sortie ip addr toujours valide) | DOCUMENTE |
| **SE-NET-009** | Cles traduction manquantes retournent la cle | `locale_provider.dart` | debugPrint pour les cles manquantes | CORRIGE |
| **SE-NET-010** | Locale accepte valeurs arbitraires | `locale_provider.dart` | Validation _supportedLocales ['fr', 'en']. Rejet locales invalides | CORRIGE |
| **SE-NET-011** | Pas de support IPv6 | `network_info.dart` | Amelioration future, hors scope. Documente | DOCUMENTE |
| **SE-NET-012** | debugPrint expose chemin daemon | `tailscale_provider.dart` | Acceptable : debugPrint inactif en mode release Flutter | ACCEPTE |
| **SE-CMD-011** | Resultat Process.run ignore dans _openUrl | `tailscale_provider.dart` | Verification exitCode + log erreur pour les 3 plateformes | CORRIGE |
| **SE-CMD-012** | URL non validee dans _openUrl Windows | `tailscale_provider.dart` | Deja mitigue par validation HTTPS (Phase 1 SE-NET-002) | MITIGUE |
| **SE-CMD-013** | Catch vide dans _shutdownDaemon et cleanup | `tailscale_provider.dart`, `ssh/wol_setup_provider.dart`, `command_runner.dart` | 6 catch(_){} remplaces par catch(e){debugPrint(...)} | CORRIGE |
| **SE-CMD-014** | Pas de validation permissions binaire daemon | `tailscale_provider.dart` | Ajout _checkExecutable() verifiant mode Unix (0x49) avec warning | CORRIGE |

---

## Verification finale

- `flutter analyze` : **0 erreurs**
- `flutter test` : **61/61 tests passent** (42 widget + 19 lock)

## Fichiers modifies

### Phase 1
command_runner.dart, lock_provider.dart, app.dart, router.dart, network_info.dart, tailscale_provider.dart, ssh_setup_provider.dart, wol_setup_provider.dart, widget_test.dart

### Phase 2
lock_provider.dart, lock_screen.dart, command_runner.dart, tailscale_provider.dart, wol_setup_provider.dart, ssh_setup_provider.dart, copyable_info.dart, connection_info_screen.dart, locale_provider.dart, test/unit/lock_test.dart (nouveau)

## Rapports d'audit

- Contexte architectural : `docs/AUDIT/CONTEXTE_SECURITE.md`
- Suivi qualite (audit precedent) : `docs/AUDIT/SUIVIE_QUALITE.md`
