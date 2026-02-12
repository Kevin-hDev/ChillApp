# ChillApp — Spécification V1

## Qu'est-ce que Chill ?

**Chill** est un écosystème d'applications conçu pour les créateurs, les vibe coders et tous ceux qui veulent des outils simples et efficaces. L'idée : proposer une suite d'apps qui fonctionnent ensemble, avec une interface claire et sans prise de tête.

**ChillApp** est le hub central de cet écosystème. C'est l'application bureau (Windows, Linux, macOS) qui permet de configurer et gérer toutes les apps Chill depuis un seul endroit, sans toucher au terminal ni taper de commandes.

## Pour qui ?

- **Vibe coders** : des gens créatifs qui utilisent l'IA pour coder mais qui ne maîtrisent pas les détails techniques
- **Débutants** : des utilisateurs qui veulent tout configurer en quelques clics sans se perdre dans la documentation
- **Tout le monde** : quiconque préfère un bouton "Configurer" plutôt qu'un terminal

## Pourquoi ?

Configurer SSH, Wake-on-LAN ou d'autres services demande de taper des commandes dans un terminal. Pour quelqu'un qui n'est pas développeur, c'est intimidant et source d'erreurs. ChillApp résout ça : on coche une case, on clique sur un bouton, et c'est fait.

## Le lien Chill ↔ ChillShell

- **ChillShell** = l'app mobile (iOS/Android) qui sert de terminal SSH pour se connecter à ses machines à distance
- **ChillApp** = l'app bureau qui prépare les machines pour ChillShell (installer SSH, activer le Wake-on-LAN, récupérer les infos de connexion)

En V1, ChillApp supporte uniquement ChillShell. Quand de nouvelles apps Chill arriveront, ChillApp les intégrera aussi.

---

## Fonctionnalités V1

### 1. Dashboard (Tableau de bord)

Écran d'accueil avec :
- Le logo Chill et un message de bienvenue
- Les cartes de navigation vers chaque fonctionnalité
- Un indicateur visuel de l'état de configuration (fait / pas fait)

### 2. Configuration SSH

Installe et active le serveur SSH pour que ChillShell puisse se connecter à ce PC.

**Ce que ça fait :**
- Installe le serveur SSH (OpenSSH)
- Démarre le service et l'active au démarrage
- Vérifie que le service fonctionne
- Configure le pare-feu si nécessaire
- Affiche les infos de connexion (IP + nom d'utilisateur)

### 3. Configuration Wake-on-LAN

Active le Wake-on-LAN pour pouvoir allumer ce PC à distance depuis ChillShell.

**Ce que ça fait :**
- Trouve la carte réseau Ethernet
- Active le Wake on Magic Packet
- Autorise le réveil par le réseau
- Désactive le démarrage rapide (Windows)
- Crée un service de persistance (Linux)
- Affiche l'adresse MAC

**Note :** Le WoL n'est disponible que sur Windows et Linux (pas Mac en V1).

### 4. Infos de connexion

Affiche toutes les informations nécessaires pour configurer ChillShell :
- Adresse IP
- Adresse MAC (pour WoL)
- Nom d'utilisateur
- Nom de la carte réseau

### 5. Réglages

- Thème : sombre (par défaut) / clair
- Langue : français (par défaut) / anglais

---

## Commandes OS intégrées

### SSH — Windows (6 commandes)

| # | Commande | Rôle |
|---|---------|------|
| 1 | `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` | Installer le client SSH |
| 2 | `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` | Installer le serveur SSH |
| 3 | `Start-Service sshd` | Démarrer le service SSH |
| 4 | `Set-Service -Name sshd -StartupType Automatic` | Activer SSH au démarrage |
| 5 | `Get-NetFirewallRule -Name *ssh*` | Vérifier la règle pare-feu |
| 6 | `New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22` | Créer la règle pare-feu si absente |

### SSH — Linux (7 commandes, selon distro)

| # | Commande | Rôle |
|---|---------|------|
| 1a | `sudo apt update -qq && sudo apt install openssh-server -y -qq` | Installer SSH (Debian/Ubuntu) |
| 1b | `sudo dnf install openssh-server -y -q` | Installer SSH (Fedora/RHEL) |
| 1c | `sudo pacman -S --noconfirm openssh` | Installer SSH (Arch/Manjaro) |
| 2 | `sudo systemctl enable --now sshd` | Démarrer et activer SSH |
| 3 | `systemctl is-active --quiet sshd` | Vérifier que SSH tourne |
| 4a | `sudo ufw allow ssh` | Ouvrir le pare-feu (Ubuntu/Debian avec ufw) |
| 4b | `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload` | Ouvrir le pare-feu (Fedora avec firewalld) |
| 5 | `hostname -I` | Afficher l'adresse IP |

### SSH — Mac (3 commandes)

| # | Commande | Rôle |
|---|---------|------|
| 1 | `sudo systemsetup -setremotelogin on` | Activer l'accès à distance (SSH) |
| 2 | `sudo systemsetup -getremotelogin` | Vérifier que SSH est actif |
| 3 | `ipconfig getifaddr en0` / `ipconfig getifaddr en1` | Afficher l'adresse IP |

### WoL — Windows (4 commandes)

| # | Commande | Rôle |
|---|---------|------|
| 1 | `Get-NetAdapter \| Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Wi-Fi*' -and ... }` | Trouver la carte Ethernet |
| 2 | `Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Wake on Magic Packet' -DisplayValue 'Enabled'` | Activer Wake on Magic Packet |
| 3 | `powercfg /deviceenablewake $desc` | Autoriser le réveil par le réseau |
| 4 | `reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f` | Désactiver le démarrage rapide |

### WoL — Linux (5 commandes)

| # | Commande | Rôle |
|---|---------|------|
| 1a | `sudo apt install ethtool -y -qq` | Installer ethtool (Debian/Ubuntu) |
| 1b | `sudo dnf install ethtool -y -q` | Installer ethtool (Fedora/RHEL) |
| 1c | `sudo pacman -S --noconfirm ethtool` | Installer ethtool (Arch/Manjaro) |
| 2 | Scan `/sys/class/net/` | Trouver l'interface Ethernet |
| 3 | `sudo ethtool -s $ETH_IFACE wol g` | Activer le Wake-on-LAN |
| 4 | Créer `/etc/systemd/system/wol-enable.service` | Service systemd de persistance |
| 5 | `sudo systemctl daemon-reload && sudo systemctl enable wol-enable.service` | Activer le service au démarrage |

### Infos connexion (toutes plateformes)

| Info | Windows | Linux | Mac |
|------|---------|-------|-----|
| IP | `(Get-NetIPAddress -AddressFamily IPv4).IPAddress` | `hostname -I` | `ipconfig getifaddr en0` |
| MAC | `(Get-NetAdapter).MacAddress` | `cat /sys/class/net/$iface/address` | N/A en V1 |
| Utilisateur | `$env:USERNAME` | `whoami` | `whoami` |

---

## Architecture technique

### Stack

| Technologie | Version | Rôle |
|-------------|---------|------|
| Flutter | 3.38.7 | Framework d'interface multi-plateforme |
| Dart | 3.10.7 | Langage de programmation |
| flutter_riverpod | ^3.2.1 | Gestion d'état (providers) |
| go_router | ^16.2.2 | Navigation entre écrans |
| shared_preferences | ^2.5.4 | Sauvegarde des préférences (thème, langue) |
| google_fonts | ^8.0.1 | Polices Google (Plus Jakarta Sans, JetBrains Mono) |

### Plateformes cibles

- Windows (desktop)
- Linux (desktop)
- macOS (desktop)

### Exécution de commandes

Les commandes sont exécutées via `dart:io` (`Process.run`). Chaque commande est lancée avec les bons paramètres selon l'OS détecté.

**Élévation de privilèges :**
- **Windows** : PowerShell avec `-Verb RunAs` ou vérification `net session`
- **Linux** : `pkexec` (interface graphique pour sudo)
- **macOS** : `osascript -e 'do shell script "..." with administrator privileges'`

### Design system

Reprend exactement le design du site web Chill :

**Couleurs (thème sombre — par défaut) :**
- Fond principal : `#08090a`
- Fond élevé : `#111214`
- Fond surface : `#161719`
- Bordure : `#1e2025`
- Texte principal : `#f7f8f8`
- Texte secondaire : `#8a8f98`
- Accent (vert) : `#10B981`
- Accent hover : `#34d399`

**Couleurs (thème clair) :**
- Fond principal : `#fafafa`
- Fond élevé : `#ffffff`
- Fond surface : `#f4f4f5`
- Bordure : `#e5e7eb`
- Texte principal : `#111214`
- Texte secondaire : `#6b7280`
- Accent (vert) : `#059669`
- Accent hover : `#047857`

**Polices :**
- Titres : JetBrains Mono (monospace, bold)
- Corps : Plus Jakarta Sans (sans-serif)
- Code : JetBrains Mono (monospace)

**Rayons de bordure :**
- sm: 4px, md: 6px, lg: 8px, xl: 12px, 2xl: 16px

---

## Écrans

### 1. Dashboard (`/`)
- Logo Chill + "Bienvenue sur Chill"
- Cartes cliquables : SSH Setup, WoL Setup, Infos connexion
- Badge d'état sur chaque carte (configuré / pas encore)

### 2. SSH Setup (`/ssh`)
- Détection auto de l'OS
- Liste des étapes avec cases à cocher
- Bouton "Tout configurer" qui lance les commandes une par une
- Indicateur de progression pour chaque étape
- Résultat final : succès ou erreur avec message explicatif

### 3. WoL Setup (`/wol`)
- Détection auto de l'OS (masqué si Mac)
- Rappel : "Le BIOS doit être configuré manuellement"
- Mêmes cases à cocher + bouton que SSH Setup
- Affichage de l'adresse MAC à la fin

### 4. Infos connexion (`/info`)
- Affichage automatique de l'IP, MAC, nom d'utilisateur
- Bouton "Copier" pour chaque info
- Rafraîchissement possible

### 5. Réglages (`/settings`)
- Toggle thème sombre/clair
- Sélecteur de langue FR/EN
