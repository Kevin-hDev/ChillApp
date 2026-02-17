# Suivi Audit Qualite — ChillApp

> Audit realise par 4 agents paralleles (structure, widgets, providers, doublons).
> Corrections appliquees en 3 phases avec 6 agents.

---

## Resume

| Severite | Total | Corriges | Reportes |
|----------|-------|----------|----------|
| CRITIQUE | 6     | 6        | 0        |
| IMPORTANT| 14    | 14       | 0        |
| MINEUR   | 14    | 14       | 0        |
| **Total**| **34**| **34**   | **0**    |

---

## CRITIQUE

### C1 — Injection de commandes dans `runElevated`
- **Fichier :** `lib/core/command_runner.dart`
- **Probleme :** Les arguments n'etaient pas echappes avant injection dans les commandes PowerShell (Windows) et osascript (macOS)
- **Correction :** Ajout d'echappement des double-quotes pour Windows (`a.replaceAll('"', '\\"')`) et echappement `\`, `"`, `$` pour macOS
- **Statut :** Corrige (Phase 1A)

### C2 — Injection via `adapterName` dans WoL PowerShell
- **Fichier :** `lib/features/wol_setup/wol_setup_provider.dart`
- **Probleme :** Le nom de l'adaptateur reseau etait injecte directement dans les commandes PowerShell
- **Correction :** Ajout de `adapterName.replaceAll("'", "''")` pour echapper les apostrophes PowerShell
- **Statut :** Corrige (Phase 1A)

### C3 — PIN hashe sans salt
- **Fichier :** `lib/features/lock/lock_provider.dart`
- **Probleme :** Le PIN etait hashe avec SHA-256 seul, vulnerable aux rainbow tables
- **Correction :** Generation d'un salt aleatoire de 16 bytes (`Random.secure()`), stocke dans SharedPreferences (`pin_salt`). Le hash est maintenant `sha256('$salt:$pin')`
- **Statut :** Corrige (Phase 1B)

### C4 — Pas de rate limiting sur le PIN
- **Fichier :** `lib/features/lock/lock_provider.dart`
- **Probleme :** Tentatives de PIN illimitees = brute force possible
- **Correction :** Blocage de 30 secondes apres 5 echecs. Compteur `failedAttempts` et `lockedUntil` persistes dans SharedPreferences. Message affiche dans `lock_screen.dart`
- **Statut :** Corrige (Phase 1B)

### C5 — Accessibilite du pave numerique
- **Fichier :** `lib/features/lock/lock_screen.dart`
- **Probleme :** Les boutons du pave numerique n'avaient pas de `Semantics` pour les lecteurs d'ecran
- **Correction :** Ajout de `Semantics(button: true, label: ...)` sur chaque touche. Extraction du pave dans `lib/shared/widgets/num_pad.dart` avec Semantics integrees
- **Statut :** Corrige (Phase 1B + Phase 2D)

### C6 — Fichiers temporaires previsibles
- **Fichiers :** `lib/features/ssh_setup/ssh_setup_provider.dart`, `lib/features/wol_setup/wol_setup_provider.dart`
- **Probleme :** Utilisation de chemins fixes (`/tmp/chill-ssh-setup.sh`, `/tmp/chill-wol-setup.sh`) = risque TOCTOU
- **Correction :** Remplacement par `Directory.systemTemp.createTemp('chill-')` pour des dossiers temporaires uniques. Suppression du dossier entier dans le `finally`
- **Statut :** Corrige (Phase 1A)

---

## IMPORTANT

### I1 — Widget `CopyableInfo` duplique 3 fois
- **Fichiers sources :** `ssh_setup_screen.dart`, `wol_setup_screen.dart`, `tailscale_screen.dart`
- **Correction :** Extraction dans `lib/shared/widgets/copyable_info.dart`. Remplacement des 3 copies locales
- **Statut :** Corrige (Phase 1C + Phase 2)

### I2 — Widget `ExplanationCard` duplique 3 fois
- **Fichiers sources :** `ssh_setup_screen.dart`, `wol_setup_screen.dart`, `tailscale_screen.dart`
- **Correction :** Extraction dans `lib/shared/widgets/explanation_card.dart`. Remplacement des 3 copies
- **Statut :** Corrige (Phase 1C + Phase 2)

### I3 — Widgets `AnimatedLoader` et `PatienceMessage` dupliques
- **Fichiers sources :** `ssh_setup_screen.dart`, `wol_setup_screen.dart`, `tailscale_screen.dart`
- **Correction :** Extraction dans `lib/shared/widgets/animated_loader.dart` et `lib/shared/widgets/patience_message.dart`
- **Statut :** Corrige (Phase 1C + Phase 2)

### I4 — Bloc d'erreur `ErrorBanner` duplique 4 fois
- **Fichiers sources :** Ecrans SSH, WoL, Tailscale, connection_info
- **Correction :** Extraction dans `lib/shared/widgets/error_banner.dart`. Remplacement des 4 blocs inline
- **Statut :** Corrige (Phase 1C + Phase 2)

### I5 — Logique reseau dupliquee entre 3 providers
- **Fichiers sources :** `ssh_setup_provider.dart`, `wol_setup_provider.dart`, `connection_info_provider.dart`
- **Correction :** Creation de `lib/core/network_info.dart` centralisant `getEthernetIp()`, `getWifiIp()`, `getUsername()`, `getMacAddress()`, `findEthernetAdapter()`. Elimination de ~300 lignes dupliquees. `connection_info_provider.dart` passe de 261 a 106 lignes
- **Statut :** Corrige (Phase 1C + Phase 2)

### I6 — WoL dependait de SSH provider pour `StepStatus`
- **Fichier source :** `wol_setup_provider.dart` importait `ssh_setup_provider.dart`
- **Correction :** Extraction de `StepStatus` et `SetupStep` dans `lib/shared/models/setup_step.dart`. Les deux providers importent desormais le modele partage
- **Statut :** Corrige (Phase 1C + Phase 2)

### I7 — Couleurs amber hardcodees dans WoL
- **Fichier :** `wol_setup_screen.dart`
- **Probleme :** Couleurs `0xFFF59E0B` et `0xFFD97706` en dur au lieu des design tokens
- **Correction :** Remplacement par `context.chillOrange` via l'extension `ChillTheme`
- **Statut :** Corrige (Phase 2D)

### I8 — Pattern `isDark ? ChillColorsDark.X : ChillColorsLight.X` repete 86 fois
- **Fichiers :** Tous les ecrans et widgets
- **Correction :** Creation de `lib/shared/extensions/chill_theme.dart` avec l'extension `ChillTheme` sur `BuildContext`. Remplacement des 86 ternaires par `context.chillAccent`, `context.chillBgElevated`, etc.
- **Statut :** Corrige (Phase 1C + Phase 2)

### I9 — Formule de padding responsif copiee 6 fois
- **Fichiers :** Ecrans SSH, WoL, Tailscale, connection_info, settings, dashboard
- **Correction :** Creation de `lib/shared/helpers/responsive.dart` avec `responsivePadding(width)`. Remplacement des 6 copies
- **Statut :** Corrige (Phase 1C + Phase 2)

### I10 — Tooltips non traduits (hardcoded en francais)
- **Fichiers :** Widgets CopyableInfo, boutons retour
- **Correction :** Utilisation des cles i18n `info.copy` / `info.copied` dans le widget partage. Ajout de `tooltip` sur les boutons retour
- **Statut :** Corrige (Phase 2)

### I11 — `step_indicator.dart` importe `ssh_setup_provider.dart`
- **Fichier :** `lib/shared/widgets/step_indicator.dart`
- **Probleme :** Un widget partage ne devrait pas dependre d'une feature specifique
- **Correction :** Import remplace par `lib/shared/models/setup_step.dart`
- **Statut :** Corrige (Phase 2E)

### I12 — Race condition dans `tailscale retry()`
- **Fichier :** `lib/features/tailscale/tailscale_provider.dart`
- **Probleme :** Le processus precedent etait tue sans attendre sa terminaison
- **Correction :** Ajout de `await process.exitCode.timeout(Duration(seconds: 3), onTimeout: () => -1)` avant de relancer
- **Statut :** Corrige (Phase 1A)

### I13 — Pas de timeout sur `Process.run`
- **Fichier :** `lib/core/command_runner.dart`
- **Probleme :** Les commandes pouvaient bloquer indefiniment
- **Correction :** Ajout d'un timeout par defaut de 120 secondes. Parametre optionnel `Duration? timeout` sur `run()` et `runPowerShell()`. Gestion de `TimeoutException` et `ProcessException`
- **Statut :** Corrige (Phase 1A)

### I14 — `_shutdownDaemon` non await
- **Fichier :** `lib/features/tailscale/tailscale_provider.dart`
- **Probleme :** Le Future de `process.exitCode` n'etait pas gere
- **Correction :** Utilisation de `unawaited()` pour rendre explicite l'intention de ne pas attendre, avec timeout de 3 secondes et kill en fallback
- **Statut :** Corrige (Phase 1A)

---

## MINEUR

### M1 — `chill_button.dart` jamais utilise
- **Fichier :** `lib/shared/widgets/chill_button.dart`
- **Correction :** Fichier supprime
- **Statut :** Corrige (Phase 3F)

### M2 — `privilege_manager.dart` jamais utilise
- **Fichier :** `lib/core/privilege_manager.dart`
- **Correction :** Fichier supprime
- **Statut :** Corrige (Phase 3F)

### M3 — Pas de route 404 dans go_router
- **Fichier :** `lib/config/router.dart`
- **Correction :** Ajout d'un `errorBuilder` qui affiche une page 404 propre avec bouton retour au dashboard
- **Statut :** Corrige (Phase 3F)

### M4 — Constantes `ChillSpacing` inutilisees
- **Fichier :** `lib/config/design_tokens.dart`
- **Probleme :** `headerHeight`, `pagePadding`, `sectionGap` jamais utilisees
- **Correction :** Constantes supprimees
- **Statut :** Corrige (Phase 3F)

### M5 — `_openUrl` Windows manque le titre vide
- **Fichier :** `lib/features/tailscale/tailscale_provider.dart`
- **Probleme :** `cmd /c start URL` echoue si l'URL contient des caracteres speciaux
- **Correction :** Ajout de `''` comme titre : `cmd /c start '' URL`
- **Statut :** Corrige (Phase 1A)

### M6 — Dashboard ternaire inutile pour colonnes
- **Fichier :** `lib/features/dashboard/dashboard_screen.dart`
- **Probleme :** Calcul de colonnes avec ternaire superflu
- **Correction :** Simplifie en `final columns = width < 600 ? 2 : 3;`
- **Statut :** Corrige (Phase 2E)

### M7 — Image mascotte sans semanticLabel
- **Fichier :** `lib/features/dashboard/dashboard_screen.dart`
- **Correction :** Ajout de `semanticLabel: 'Mascotte Chill'` sur l'Image
- **Statut :** Corrige (Phase 2E)

### M8 — Boutons retour sans tooltip
- **Fichiers :** Ecrans SSH, WoL, Tailscale, connection_info, settings
- **Correction :** Ajout de `tooltip: 'Retour'` sur tous les `IconButton` de retour
- **Statut :** Corrige (Phase 2)

### M9 — Pave numerique duplique dans lock_screen
- **Fichier :** `lib/features/lock/lock_screen.dart`
- **Correction :** Extraction dans `lib/shared/widgets/num_pad.dart`. Les deux instances utilisent le widget partage
- **Statut :** Corrige (Phase 1C + Phase 2D)

### M10 — `tailscale_screen.dart` trop volumineux (739 lignes)
- **Fichier :** `lib/features/tailscale/tailscale_screen.dart`
- **Correction :** Elimination des widgets locaux dupliques + utilisation des partages. Passe de 739 a 437 lignes
- **Statut :** Corrige (Phase 2E)

### M11 — StreamSubscription non stockees dans Tailscale
- **Fichier :** `lib/features/tailscale/tailscale_provider.dart`
- **Probleme :** Les subscriptions stdout/stderr n'etaient pas annulees proprement
- **Correction :** Ajout de `_stdoutSub` et `_stderrSub` avec annulation dans `_shutdownDaemon()`
- **Statut :** Corrige (Phase 1A)

### M12 — `catch (_)` silencieux pour erreurs JSON
- **Fichier :** `lib/features/tailscale/tailscale_provider.dart`
- **Correction :** Remplacement par `catch (e) { debugPrint('Chill: JSON parse error: $e'); }`
- **Statut :** Corrige (Phase 1A)

### M13 — OsDetector sans fallback `ID_LIKE`
- **Fichier :** `lib/core/os_detector.dart`
- **Probleme :** Les distros derivees (Zorin, Elementary, Pop!_OS) n'etaient pas reconnues
- **Correction :** Ajout de lecture de `ID_LIKE` dans `/etc/os-release` quand `ID` ne correspond pas a une distro connue
- **Statut :** Corrige (Phase 3F)

### M14 — Imports de tests casses
- **Fichiers :** `test/widget_test.dart`, `test/unit/state_test.dart`
- **Correction :** Mise a jour des imports pour `setup_step.dart`. Ajout d'overrides de providers pour eviter les timers pendants en test
- **Statut :** Corrige (Phase 3F + correction post-phase)

---

## Fichiers crees

| Fichier | Description |
|---------|-------------|
| `lib/shared/models/setup_step.dart` | Modele `StepStatus` + `SetupStep` partage |
| `lib/shared/extensions/chill_theme.dart` | Extension `ChillTheme` sur `BuildContext` |
| `lib/shared/helpers/responsive.dart` | Helper `responsivePadding(width)` |
| `lib/core/network_info.dart` | Service reseau centralise |
| `lib/shared/widgets/copyable_info.dart` | Widget info copiable |
| `lib/shared/widgets/explanation_card.dart` | Carte explicative |
| `lib/shared/widgets/animated_loader.dart` | Loader anime |
| `lib/shared/widgets/patience_message.dart` | Message patience avec fade |
| `lib/shared/widgets/error_banner.dart` | Banniere d'erreur |
| `lib/shared/widgets/num_pad.dart` | Pave numerique accessible |

## Fichiers supprimes

| Fichier | Raison |
|---------|--------|
| `lib/shared/widgets/chill_button.dart` | Code mort (jamais importe) |
| `lib/core/privilege_manager.dart` | Code mort (jamais importe) |

## Verification finale

- `flutter analyze` : 0 erreur, 0 warning
- `flutter test` : 42 tests OK
