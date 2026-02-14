# Chill CLI — Commandes terminal

## Installation

**Linux / macOS :**
```bash
curl -fsSL https://chill.app/install.sh | bash
```

**Windows (PowerShell) :**
```powershell
irm https://chill.app/install.ps1 | iex
```

---

## Commandes disponibles

| Commande | Description |
|----------|-------------|
| `chill version` | Affiche la version installée |
| `chill status` | Résumé SSH / WoL / Tailscale / Firewall / App |
| `chill info` | Affiche hostname, IP (Ethernet, Wi-Fi, Tailscale), MAC |
| `chill start` | Lance l'application graphique |
| `chill stop` | Ferme l'application |
| `chill update` | Met à jour vers la dernière version (depuis GitHub) |
| `chill uninstall` | Désinstalle Chill proprement |
| `chill autostart on\|off` | Active/désactive le lancement au démarrage |
| `chill doctor` | Diagnostic complet de l'installation |
| `chill security` | Checkup de sécurité du système |
| `chill logs` | Affiche les derniers logs |
| `chill reset` | Remet tous les réglages à zéro |
| `chill help` | Affiche l'aide |

---

## Détail par commande

### `chill version`
Lit le fichier `VERSION` inclus dans le bundle et affiche le numéro de version.

### `chill status`
Vérifie l'état de chaque service :
- **SSH** : `systemctl` (Linux), `systemsetup` (macOS), `Get-Service sshd` (Windows)
- **Wake-on-LAN** : service WoL (Linux), adaptateur réseau (Windows)
- **Tailscale** : `tailscale status`
- **Firewall** : UFW (Linux), socketfilterfw (macOS), `Get-NetFirewallProfile` (Windows)
- **App Chill** : vérifie si le processus `chill_app` tourne

### `chill info`
Affiche les infos de connexion :
- Hostname
- Nom d'utilisateur
- IP Ethernet + adresse MAC
- IP Wi-Fi
- IP Tailscale (si connecté)

### `chill start`
Lance `chill_app` en arrière-plan (`nohup` sur Linux/macOS, `Start-Process` sur Windows).
Vérifie d'abord que l'app ne tourne pas déjà.

### `chill stop`
Arrête le processus `chill_app` (`pkill` sur Linux/macOS, `Stop-Process` sur Windows).

### `chill update`
1. Détecte l'OS et l'architecture
2. Contacte l'API GitHub pour trouver la dernière release
3. Télécharge l'archive correspondante
4. Stoppe l'app si elle tourne
5. Extrait et remplace les fichiers
6. Affiche l'ancienne et la nouvelle version

### `chill uninstall`
Demande confirmation puis supprime :
- Le dossier d'installation (`~/.local/share/chill/` ou `%LOCALAPPDATA%\Chill\`)
- Le symlink CLI (`~/.local/bin/chill`) ou l'entrée PATH Windows
- Le lanceur d'application (`.desktop` Linux / raccourcis Bureau + Menu Démarrer Windows)
- Les préférences utilisateur

### `chill autostart on|off`
- **Linux** : crée/supprime un fichier `.desktop` dans `~/.config/autostart/`
- **Windows** : ajoute/supprime une entrée dans le registre `HKCU\...\Run`

### `chill doctor`
Vérifie point par point :
- Binaire app présent et exécutable
- Daemon Tailscale présent
- Fichier VERSION lisible
- CLI accessible dans le PATH
- Tailscale installé sur le système
- Lanceur d'application créé
- Démarrage automatique configuré ou non
- Dossier de préférences existant

### `chill security`

**Linux :**
- Firewall UFW actif
- Root login SSH désactivé
- Fail2ban actif
- Mises à jour automatiques
- IP forwarding désactivé
- Permissions `/etc/shadow`

**macOS :**
- Firewall actif
- Gatekeeper actif
- Mode furtif activé
- Mises à jour automatiques

**Windows :**
- Firewall Windows (tous les profils)
- Bureau à distance (RDP) désactivé
- SMBv1 désactivé
- Mises à jour automatiques
- UAC activé
- Windows Defender (temps réel)
- SSH root login

### `chill logs`
- **Linux** : `journalctl --user -u chill -n 50`
- **Windows** : Event Viewer (erreurs liées à Chill)
- Note : l'app n'écrit pas encore de logs système

### `chill reset`
Demande confirmation puis supprime le dossier de préférences :
- Linux/macOS : `~/.local/share/chill_app/`
- Windows : `%APPDATA%\chill_app\`

Réinitialise : thème, langue, PIN, onboarding.

---

## Fichiers concernés

| Fichier | Emplacement | Rôle |
|---------|-------------|------|
| `cli/chill` | ChillApp | CLI bash (Linux/macOS) |
| `cli/chill.ps1` | ChillApp | CLI PowerShell (Windows) |
| `public/install.sh` | Site Chill | Installeur Linux/macOS |
| `public/install.ps1` | Site Chill | Installeur Windows |
| `scripts/package-release.sh` | ChillApp | Packaging des releases GitHub |

---

## Chemins d'installation

| OS | Dossier app | CLI | Préférences |
|----|------------|-----|-------------|
| Linux | `~/.local/share/chill/` | `~/.local/bin/chill` | `~/.local/share/chill_app/` |
| macOS | `~/.local/share/chill/` | `~/.local/bin/chill` | `~/.local/share/chill_app/` |
| Windows | `%LOCALAPPDATA%\Chill\` | Dans le PATH via registre | `%APPDATA%\chill_app\` |

---

## Convention de noms des releases GitHub

| Plateforme | Archive |
|-----------|---------|
| Linux x64 | `chill-linux-x64.tar.gz` |
| macOS x64 | `chill-macos-x64.tar.gz` |
| macOS ARM | `chill-macos-arm64.tar.gz` |
| Windows x64 | `chill-windows-x64.zip` |

## Contenu d'une archive (exemple Linux)

```
chill-linux-x64/
├── chill_app           # Application Flutter
├── lib/                # Bibliothèques Flutter (.so)
├── data/               # Assets Flutter
├── chill-tailscale     # Daemon Go Tailscale
├── chill               # CLI wrapper bash
└── VERSION             # Numéro de version
```
