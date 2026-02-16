<div align="center">

# Chill

**Configure SSH, Wake-on-LAN et Tailscale — en trois clics.**

![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

*Une app desktop gratuite qui regroupe tout ce qu'il faut pour l'accès à distance.*
*Configure SSH, active Wake-on-LAN et connecte-toi à Tailscale — sans rien installer d'autre.*

[📥 Installation](#-démarrage-rapide) · [📖 Documentation](#-documentation) · [🔒 Sécurité](SECURITY.md)

</div>

---

> **⚠️ IMPORTANT :** Chill nécessite des **privilèges administrateur** pour configurer les services système.
> [**Lis ceci avant d'installer →**](⚠️_LISEZ_CECI_AVANT_INSTALLATION.md)

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
**⚠️ [Lis ceci avant d'installer](⚠️_LISEZ_CECI_AVANT_INSTALLATION.md)**

**Audits professionnels :**
- 2 audits internes + audit qualité (méthodologie Trail of Bits)
- 38 findings corrigés (4 Critical, 8 High, 14 Medium, 12 Low)
- 61 tests unitaires passent après corrections
- Voir [SECURITY.md](SECURITY.md) pour le rapport complet

**Onglet Sécurité OS :**
- Toggles sécurité (8 Windows, 7 Linux, 8 macOS)
- Checkup système avec scan 12 points
- Recommandations personnalisées
- 100% local, aucune donnée envoyée sur le réseau

---

## 🤝 Le duo Chill + ChillShell

**Chill** (cette app) prépare ton PC.
**[ChillShell](https://github.com/Kevin-hDev/ChillShell)** (app mobile) te connecte depuis ton téléphone.

Ensemble, ils forment le **pont parfait pour le vibe coding** : code depuis ton canapé, un café, n'importe où. Lance Claude Code, Codex CLI, Gemini ou n'importe quel agent IA — directement depuis ton mobile.

---

## 🚀 Démarrage rapide

### Prérequis

**⚠️ [Lis ceci d'abord](⚠️_LISEZ_CECI_AVANT_INSTALLATION.md) avant d'installer !**

- **Flutter 3.27+** ou supérieur
- **Dart 3.5+** ou supérieur
- **Privilèges administrateur** (admin/sudo/root) pour configuration système
- **Windows 10/11**, **Ubuntu 20.04+/Debian 11+/Fedora 35+/Arch**, ou **macOS 11+**

### Installation depuis les sources

```bash
# Clone le repo
git clone https://github.com/YOUR_ORG/Chill.git
cd Chill

# Installe les dépendances
flutter pub get

# Lance l'application
flutter run -d linux    # Pour Linux
flutter run -d windows  # Pour Windows
flutter run -d macos    # Pour macOS
```

**Note Linux :** Flutter doit être installé via git (pas snap). Le paquet `lld-18` est requis sur Ubuntu.

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
| **Flutter** | 3.27+ | Framework d'interface multi-plateforme |
| **Dart** | 3.5+ | Langage de programmation |
| **flutter_riverpod** | ^3.2.1 | Gestion d'état (providers) |
| **go_router** | ^16.2.2 | Navigation entre écrans |
| **shared_preferences** | ^2.5.4 | Sauvegarde des préférences (thème, langue, PIN) |
| **google_fonts** | ^8.0.1 | Polices Google (Plus Jakarta Sans, JetBrains Mono) |
| **Go daemon** | 1.21+ | Daemon Tailscale (tsnet) pour intégration native |

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

Voir [ROADMAP.md](ROADMAP.md) pour la feuille de route complète.

### ✅ V1.0 — Released (Février 2026)
- [x] Application desktop multi-plateforme (Windows, Linux, macOS)
- [x] Configuration SSH automatique (7 étapes Windows, 5 Linux, 3 macOS)
- [x] Configuration Wake-on-LAN (Windows/Linux)
- [x] Intégration Tailscale native (daemon Go tsnet)
- [x] Infos de connexion auto-détectées
- [x] Verrouillage PIN (8 chiffres, SHA-256 hashé)
- [x] Support bilingue (FR/EN)
- [x] Thèmes sombre et clair
- [x] 97 tests unitaires

### 🔧 V1.1 — En Développement
- [ ] **Onglet Sécurité OS** (feature majeur)
  - Toggles sécurité (8 Windows, 7 Linux, 8 macOS)
  - Checkup système 12 points avec score
  - Recommandations personnalisées

### 🔮 Versions Futures
- **V1.2** — Diagnostics d'erreur améliorés
- **V1.3** — Support Linux étendu (openSUSE, Gentoo, Alpine)
- **V1.4** — Features SSH avancées (port custom, 2FA, sshd hardening)
- **V1.5** — Localization (ES, DE, ZH, PT, IT)
- **V2.0** — Config avancée (profils, batch, CLI mode, network discovery)

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

**Plateformes supportées :** Windows 10/11, Linux (Ubuntu/Debian/Fedora/Arch), macOS 11+ (Big Sur et ultérieur).

---

## 📄 Licence

Ce projet est sous **GNU General Public License v3.0 (GPL v3)**.

**Ce que cela signifie :**
- ✅ Gratuit et open source pour toujours
- ✅ Tu peux utiliser, modifier, redistribuer
- ⚠️ Les modifications doivent rester GPL v3
- ❌ Pas de versions propriétaires/fermées

Voir [LICENSE](LICENSE) pour le texte complet.

**Pourquoi GPL v3 ?** Pour garantir que Chill reste libre et accessible à tous, sans dérive commerciale fermée.

---

## 👨‍💻 Auteur

**Kevin HUYNH** — [Chill_app@outlook.fr](mailto:Chill_app@outlook.fr)

*Fait avec ❤️ et Flutter*

---

## 🤝 Contribution

Les contributions sont les bienvenues ! 🎉

**Avant de contribuer :**
1. Lis [⚠️_READ_THIS_FIRST.md](⚠️_READ_THIS_FIRST.md) pour comprendre le modèle de sécurité
2. Consulte [CONTRIBUTING.md](CONTRIBUTING.md) pour les standards de code et procédures
3. Vérifie les [Issues](https://github.com/YOUR_ORG/Chill/issues) pour voir les tâches disponibles

**Trouver une faille de sécurité ?**
🚫 Ne pas ouvrir une issue publique → 📧 Email privé : [Chill_app@outlook.fr](mailto:Chill_app@outlook.fr)

Voir [SECURITY.md](SECURITY.md) pour la procédure de divulgation responsable.

---

## 📚 Documentation

- [⚠️ À LIRE EN PREMIER](⚠️_LISEZ_CECI_AVANT_INSTALLATION.md) — Avertissements et prérequis
- [SECURITY.md](SECURITY.md) — Audits de sécurité et mesures implémentées
- [CONTRIBUTING.md](CONTRIBUTING.md) — Guide de contribution
- [CHANGELOG.md](CHANGELOG.md) — Historique des versions
- [ROADMAP.md](ROADMAP.md) — Feuille de route et features planifiées

---

<div align="center">

**Fait avec ❤️ et Flutter**

*Chill — Parce que configurer devrait être simple.*

</div>
