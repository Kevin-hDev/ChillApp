# CLAUDE.md — ChillApp

## Communication

- **Toujours répondre en français.** L'utilisateur ne parle pas anglais.
- **Expliquer simplement, sans jargon technique.** L'utilisateur n'est pas développeur. Privilégier des phrases courtes et concrètes.

## User Preferences

- **Langue** : L'utilisateur parle uniquement français. Toujours répondre en français, éviter l'anglais.
- **Recherche web** : Utiliser le MCP Brave Search (`mcp__brave-search__brave_web_search`) pour toutes les recherches web.
- **Skills** : Utiliser les skills disponibles selon la situation. Skills clés :
  - `superpowers:brainstorming` - Avant tout travail créatif (nouvelles features, composants)
  - `superpowers:writing-plans` - Pour planifier l'implémentation d'une tâche multi-étapes
  - `superpowers:test-driven-development` - Pour implémenter features/bugfixes
  - `superpowers:systematic-debugging` - Face à un bug ou comportement inattendu, quand tu n'arrives pas à résoudre un problème/BUG au bout de deux essaies tu utilises systématiquement systematic-debugging pour investiguer en profondeur 
  - `superpowers:verification-before-completion` - Avant de dire qu'un travail est terminé
  - `interface-design` - Pour le design d'interfaces (dashboards, apps)
  - `Front-end design` - pour éviter les designs classiques qui font trop IA
  - `Claudeception` - Pour que tu prennes des notes des que tu apprends quelques chose de pertinents 

## Commandes

```bash
flutter run -d linux        # Lancer l'app sur Linux
flutter run -d windows      # Lancer l'app sur Windows
flutter run -d macos        # Lancer l'app sur macOS
flutter build linux          # Build production Linux
flutter build windows        # Build production Windows
flutter build macos          # Build production macOS
flutter pub get              # Installer les dépendances
flutter test                 # Lancer les tests
```

## Architecture

### Stack technique
- **Flutter 3.38.7** — Framework d'interface desktop multi-plateforme
- **Dart 3.10.7** — Langage de programmation
- **flutter_riverpod ^3.2.1** — Gestion d'état (providers pour l'état de chaque étape de configuration)
- **go_router ^16.2.2** — Navigation entre les 5 écrans
- **shared_preferences ^2.5.4** — Sauvegarde des préférences utilisateur (thème, langue)
- **google_fonts ^8.0.1** — Polices Google Fonts (Plus Jakarta Sans, JetBrains Mono)

### Structure du projet

```
lib/
├── main.dart                    # Point d'entrée (ProviderScope + runApp)
├── app.dart                     # MaterialApp.router + thème
├── config/
│   ├── design_tokens.dart       # Couleurs, polices, espacements
│   ├── router.dart              # Routes go_router (/, /ssh, /wol, /info, /settings)
│   └── theme.dart               # ThemeData basé sur design_tokens
├── core/
│   ├── command_runner.dart       # Abstraction pour Process.run
│   ├── os_detector.dart          # Détection Windows/Linux/Mac
│   └── privilege_manager.dart    # Élévation admin/sudo/pkexec
├── i18n/
│   ├── translations.dart         # Clés de traduction FR/EN
│   └── locale_provider.dart      # Provider Riverpod pour la langue active
├── features/
│   ├── dashboard/
│   │   └── dashboard_screen.dart
│   ├── ssh_setup/
│   │   ├── ssh_setup_screen.dart
│   │   └── ssh_setup_provider.dart
│   ├── wol_setup/
│   │   ├── wol_setup_screen.dart
│   │   └── wol_setup_provider.dart
│   ├── connection_info/
│   │   └── connection_info_screen.dart
│   └── settings/
│       ├── settings_screen.dart
│       └── settings_provider.dart
└── shared/
    └── widgets/
        ├── chill_button.dart
        ├── chill_card.dart
        ├── step_indicator.dart
        └── status_badge.dart
```

### Design tokens

Les couleurs et polices reprennent exactement le design du site web Chill.

**Couleurs (thème sombre — par défaut) :**
| Token | Valeur | Usage |
|-------|--------|-------|
| bgPrimary | `#08090a` | Fond principal de l'app |
| bgElevated | `#111214` | Fond des cartes et panels |
| bgSurface | `#161719` | Fond des éléments interactifs |
| border | `#1e2025` | Bordures principales |
| textPrimary | `#f7f8f8` | Texte principal |
| textSecondary | `#8a8f98` | Texte secondaire, descriptions |
| textMuted | `#5c6170` | Texte grisé, hints |
| accent | `#10B981` | Vert accent (boutons, liens, succès) |
| accentHover | `#34d399` | Vert au survol |

**Couleurs (thème clair) :**
| Token | Valeur | Usage |
|-------|--------|-------|
| bgPrimary | `#fafafa` | Fond principal |
| bgElevated | `#ffffff` | Fond des cartes |
| bgSurface | `#f4f4f5` | Fond des éléments interactifs |
| border | `#e5e7eb` | Bordures |
| textPrimary | `#111214` | Texte principal |
| textSecondary | `#6b7280` | Texte secondaire |
| accent | `#059669` | Vert accent |
| accentHover | `#047857` | Vert au survol |

**Polices :**
- Titres : JetBrains Mono (via google_fonts, bold)
- Corps : Plus Jakarta Sans (via google_fonts)
- Code/terminal : JetBrains Mono (via google_fonts)

**Rayons de bordure :**
- sm: 4, md: 6, lg: 8, xl: 12, xxl: 16

### Pattern d'exécution de commandes

Toutes les commandes OS sont exécutées via `dart:io` `Process.run`. Le pattern est :

```dart
// 1. Détecter l'OS
final os = Platform.operatingSystem; // 'windows', 'linux', 'macos'

// 2. Choisir la commande selon l'OS
// 3. Sur Linux, détecter la distro via /etc/os-release
// 4. Exécuter avec Process.run
final result = await Process.run('executable', ['args']);

// 5. Vérifier result.exitCode == 0
// 6. Afficher succès ou erreur dans l'interface
```

**Élévation de privilèges :**
- **Windows** : `Process.run('powershell', ['-Command', 'Start-Process powershell -Verb RunAs -ArgumentList "..."'])`
- **Linux** : `Process.run('pkexec', ['commande', 'args'])` — affiche une boîte de dialogue pour le mot de passe
- **macOS** : `Process.run('osascript', ['-e', 'do shell script "..." with administrator privileges'])`

### Conventions

- Les fichiers Dart utilisent le snake_case : `ssh_setup_screen.dart`
- Les classes utilisent le PascalCase : `SshSetupScreen`
- Les providers Riverpod finissent par `Provider` : `sshSetupProvider`
- Les écrans finissent par `Screen` : `DashboardScreen`
- Les widgets partagés sont dans `shared/widgets/`
- Chaque feature a son propre dossier dans `features/`

### Bilinguisme (i18n)

- Français par défaut
- Anglais en option
- Les traductions sont dans `i18n/translations.dart` sous forme de Map
- Un provider Riverpod (`localeProvider`) gère la langue active
- Fonction helper `t(key)` pour accéder aux traductions

## Securite — Modules installes

Le dossier `lib/core/security/` contient 44 modules de securite (869 tests).
Voir `docs/TEST_HACK_RED_TEAM/Suivie_correction/BILAN_INTEGRATION.md` pour le detail.
Tout nouveau code doit respecter les regles de securite definies dans `~/.claude/CLAUDE.md`.

## RAPPEL
1. Repond moi ou commence toujours par me parle en Francais, je ne parle pas anglais.
2. Pense a utiliser le PLUGIN superpowers et ces differents skills en fonction de la tache.
3. Je n'ai pas de connaissance en programmation, je ne sais pas lire le code je peux vite etre perdu dans le langage de developper.
4. Tu codes TOUJOURS en appliquant les 10 regles de securite de `~/.claude/CLAUDE.md`. C'est non negociable.
5. On corrige les problemes, on ne se contente jamais de les camoufler comme si nous cachions de la poussiere sous un tapis.
