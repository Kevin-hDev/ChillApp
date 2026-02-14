<div align="center">

# Chill

**Configure SSH, Wake-on-LAN et Tailscale — en trois clics.**

![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

*Une app desktop gratuite qui regroupe tout ce qu'il faut pour l'accès à distance.*
*Configure SSH, active Wake-on-LAN et connecte-toi à Tailscale — sans rien installer d'autre.*

[Télécharger pour Windows](#) · [Télécharger pour Linux](#) · [Documentation](#)

</div>

---

## 🎯 Qu'est-ce que Chill ?

**Chill** est l'application desktop qui prépare ton PC pour l'accès à distance. Pas de commandes, pas de terminal, pas de lignes de config à taper — juste une interface claire et des boutons.

### Le problème

Configurer SSH, Wake-on-LAN ou d'autres services qui demande de taper des commandes dans un terminal. Pour quelqu'un qui n'est pas développeur, c'est intimidant et source d'erreurs.

### La solution

**Chill** résout ça : tu coches une case, tu cliques sur un bouton, et c'est fait. Ton PC est prêt pour les connexions à distance.

---

## ✨ Fonctionnalités

### 🔐 **Configuration SSH en un clic**
Chill installe et active le serveur SSH sur ton PC automatiquement. Pas de commandes PowerShell, pas de configuration manuelle. Clique sur « Tout configurer » et ton PC est prêt pour les connexions à distance.

### ⚡ **Wake-on-LAN simplifié**
Pour accéder à ton PC à distance, il doit être allumé. Le Wake-on-LAN te permet de le démarrer depuis ton téléphone. Chill active le WoL sur ta carte réseau, désactive le démarrage rapide et configure tout ce qu'il faut — la configuration du BIOS reste manuelle.

### 🌐 **Tailscale intégré**
Connecte ton PC à Tailscale directement depuis Chill — pas besoin d'installer Tailscale séparément. Connecte-toi ou crée un compte, et accède à ton ordinateur depuis n'importe où dans le monde.

### 📋 **Infos de connexion**
Affichage automatique de l'IP, l'adresse MAC et le nom d'utilisateur. Un bouton « Copier » pour chaque info. Parfait pour configurer [ChillShell](https://github.com/Kevin-hDev/ChillShell) ou tout autre client SSH.

### 🎨 **Interface moderne**
- Thème sombre par défaut (thème clair disponible)
- Bilingue : Français et Anglais
- Design system cohérent avec le site web Chill
- Polices : JetBrains Mono et Plus Jakarta Sans

### 🔒 **Sécurité intégrée**
Page Sécurité OS avec :
- Scan des vulnérabilités système
- Checkup de sécurité complet
- Recommandations personnalisées
- Audits de sécurité internes documentés

---

## 🤝 Le duo Chill + ChillShell

**Chill** (cette app) prépare ton PC.
**[ChillShell](https://github.com/Kevin-hDev/ChillShell)** (app mobile) te connecte depuis ton téléphone.

Ensemble, ils forment le **pont parfait pour le vibe coding** : code depuis ton canapé, un café, n'importe où. Lance Claude Code, Codex CLI, Gemini ou n'importe quel agent IA — directement depuis ton mobile.

---

## 🚀 Démarrage rapide

### Prérequis

- Flutter 3.38.7 ou supérieur
- Dart 3.10.7 ou supérieur

### Installation

```bash
# Clone le repo
git clone https://github.com/Kevin-hDev/ChillApp.git
cd ChillApp

# Installe les dépendances
flutter pub get

# Lance l'application
flutter run -d linux    # Pour Linux
flutter run -d windows  # Pour Windows
```

### Build de production

```bash
flutter build linux    # Build Linux
flutter build windows  # Build Windows
```

Les exécutables se trouvent dans :
- Linux : `build/linux/x64/release/bundle/`
- Windows : `build/windows/x64/runner/Release/`

---

## 🛠️ Stack technique

| Technologie | Version | Rôle |
|-------------|---------|------|
| **Flutter** | 3.38.7 | Framework d'interface multi-plateforme |
| **Dart** | 3.10.7 | Langage de programmation |
| **flutter_riverpod** | ^3.2.1 | Gestion d'état (providers) |
| **go_router** | ^16.2.2 | Navigation entre écrans |
| **shared_preferences** | ^2.5.4 | Sauvegarde des préférences (thème, langue) |
| **google_fonts** | ^8.0.1 | Polices Google (Plus Jakarta Sans, JetBrains Mono) |

### Design tokens

- **Accent primaire** : `#10B981` (Vert émeraude)
- **Typographie** : JetBrains Mono (titres/code), Plus Jakarta Sans (corps)
- **Thème** : Sombre par défaut avec option claire

---

## 📁 Structure du projet

```
ChillApp/
├── lib/
│   ├── main.dart                 # Point d'entrée
│   ├── app.dart                  # Configuration de l'app
│   ├── config/                   # Design tokens, thème, routing
│   ├── core/                     # Command runner, OS detection, privilèges
│   ├── i18n/                     # Traductions (FR/EN)
│   ├── features/                 # Modules de fonctionnalités
│   │   ├── dashboard/            # Écran d'accueil
│   │   ├── ssh_setup/            # Configuration SSH
│   │   ├── wol_setup/            # Configuration Wake-on-LAN
│   │   ├── connection_info/      # Infos de connexion
│   │   └── settings/             # Réglages
│   └── shared/                   # Widgets partagés
├── assets/                       # Images et ressources
├── docs/                         # Documentation
├── scripts/                      # Scripts de build et packaging
└── tailscale-daemon/             # Daemon Tailscale (Go)
```

---

## 🗺️ Roadmap

### ✅ V1 (Actuel)
- [x] Application desktop multi-plateforme (Windows, Linux)
- [x] Configuration SSH automatique
- [x] Configuration Wake-on-LAN
- [x] Intégration Tailscale native
- [x] Infos de connexion
- [x] Page Sécurité OS
- [x] Support bilingue (FR/EN)
- [x] Thèmes sombre et clair

### 🚧 À venir
- [ ] Support macOS
- [ ] Intégration ChillShell (en cours)
- [ ] Mode CLI pour automatisation
- [ ] Plugins pour extensions

---

## 🌍 Pour qui ?

- **Vibe coders** : des gens créatifs qui utilisent l'IA pour coder mais qui ne maîtrisent pas les détails techniques
- **Débutants** : des utilisateurs qui veulent tout configurer en quelques clics sans se perdre dans la documentation
- **Tout le monde** : quiconque préfère un bouton "Configurer" plutôt qu'un terminal

---

## 🤖 Agents CLI supportés

Chill prépare ton PC pour accueillir tous les agents CLI via ChillShell :

- **Claude Code** (Anthropic) — Node.js 18+
- **Codex CLI** (OpenAI/ChatGPT) — Node.js 22+
- **Cursor CLI** — Node.js 18+
- **Kimi Code** (Moonshot AI) — Python 3.12+
- **Gemini CLI** (Google) — Node.js 18+
- **Droid CLI** (Factory AI) — Node.js 18+
- **Mistral Vibe** (Mistral AI) — Python 3.10+
- **Grok CLI** (xAI) — Node.js 18+
- Et bien d'autres...

**Note** : Support Windows & Linux confirmé. Tests iOS/macOS en cours — pas de déploiement pour ces plateformes au début.

---

## 📄 Licence

Ce projet est actuellement privé et non licencié pour usage public.

---

## 👨‍💻 Auteur

**HUYNH Kevin** ([@Kevin-hDev](https://github.com/Kevin-hDev))

---

## 🤝 Contribution

Ce projet est actuellement privé. Les contributions seront acceptées une fois le projet rendu public.

---

<div align="center">

**Fait avec ❤️ et Flutter**

*Chill — Parce que configurer devrait être simple.*

</div>
