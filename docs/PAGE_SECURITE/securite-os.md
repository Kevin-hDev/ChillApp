# 🛡️ Sécurité OS — Commandes & Checkup

> **Objectif** : Page dédiée dans l'application desktop pour sécuriser l'OS de l'utilisateur.
> Deux blocs : des **toggles activables/désactivables** et un **bouton Checkup** qui analyse l'état du système.

> **Note** : SSH, Wake-on-LAN et Tailscale sont déjà configurés et gérés par l'application.
> Cette page couvre uniquement le **hardening de l'OS lui-même**.

---

## 📌 Rappel important — SSH Root Login

L'application configure déjà OpenSSH, mais il faut **vérifier que le login root par SSH est bien désactivé**.

Si ce n'est pas déjà dans le script de configuration SSH initial, ajouter cette vérification :

### Linux / macOS

```bash
# Vérifier l'état actuel
grep -i "^PermitRootLogin" /etc/ssh/sshd_config
```

- Si le résultat est `PermitRootLogin yes` ou `PermitRootLogin prohibit-password` → **à corriger**
- Valeur attendue : `PermitRootLogin no`

```bash
# Corriger si nécessaire
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### Windows (OpenSSH Server)

```powershell
# Vérifier dans le fichier de config
Get-Content "$env:ProgramData\ssh\sshd_config" | Select-String "PermitRootLogin"
```

> Sur Windows, le compte "root" n'existe pas nativement mais le compte **Administrateur** peut se connecter en SSH.
> La bonne pratique est de s'assurer que le groupe `Administrators` n'a pas d'accès SSH automatique via le fichier `administrators_authorized_keys`.

---

---

## BLOC 1 — Toggles ON/OFF (par OS)

> Chaque toggle = une commande pour activer + une commande pour désactiver.
> Maximum ~8 par OS. Tout est réversible et sans risque.

---

### 🪟 Windows 11

#### Toggle 1 — Firewall (tous les profils)

```powershell
# ✅ ACTIVER
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# ❌ DÉSACTIVER
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# 🔍 VÉRIFIER
Get-NetFirewallProfile | Select Name, Enabled
```

#### Toggle 2 — Bureau à distance (Remote Desktop)

```powershell
# ✅ DÉSACTIVER (plus sûr)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1

# ❌ RÉACTIVER
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

# 🔍 VÉRIFIER (1 = désactivé = sécurisé)
Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"
```

#### Toggle 3 — SMBv1 (protocole obsolète et dangereux)

```powershell
# ✅ DÉSACTIVER
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart

# ❌ RÉACTIVER
Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart

# 🔍 VÉRIFIER
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol | Select State
```

> **Pourquoi** : SMBv1 est le vecteur d'attaque de WannaCry et Petya. Aucun logiciel moderne n'en a besoin.

#### Toggle 4 — Service Remote Registry

```powershell
# ✅ DÉSACTIVER
Stop-Service RemoteRegistry -Force; Set-Service RemoteRegistry -StartupType Disabled

# ❌ RÉACTIVER
Set-Service RemoteRegistry -StartupType Manual; Start-Service RemoteRegistry

# 🔍 VÉRIFIER
Get-Service RemoteRegistry | Select Name, Status, StartType
```

#### Toggle 5 — Protection anti-ransomware (Controlled Folder Access)

```powershell
# ✅ ACTIVER
Set-MpPreference -EnableControlledFolderAccess Enabled

# ❌ DÉSACTIVER
Set-MpPreference -EnableControlledFolderAccess Disabled

# 🔍 VÉRIFIER
Get-MpPreference | Select EnableControlledFolderAccess
```

> **Note** : Peut bloquer certains programmes légitimes qui écrivent dans les dossiers protégés.
> L'utilisateur devra peut-être ajouter des exceptions.

#### Toggle 6 — Audit des connexions (succès + échecs)

```powershell
# ✅ ACTIVER
auditpol /set /subcategory:"Logon" /success:enable /failure:enable

# ❌ DÉSACTIVER
auditpol /set /subcategory:"Logon" /success:disable /failure:disable

# 🔍 VÉRIFIER
auditpol /get /subcategory:"Logon"
```

#### Toggle 7 — Mises à jour automatiques

```powershell
# ✅ ACTIVER (via registre — force Windows Update auto)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 4

# ❌ DÉSACTIVER (notification seulement, pas d'install auto)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 2

# 🔍 VÉRIFIER
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions"
```

#### Toggle 8 — BitLocker (chiffrement disque C:)

```powershell
# ✅ ACTIVER
Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector

# ❌ DÉSACTIVER
Disable-BitLocker -MountPoint "C:"

# 🔍 VÉRIFIER
Get-BitLockerVolume -MountPoint "C:" | Select MountPoint, VolumeStatus, EncryptionPercentage
```

> **Attention** : BitLocker nécessite TPM 2.0. L'activation génère une clé de récupération que l'utilisateur **doit absolument sauvegarder**.
> Prévoir un message d'avertissement clair dans l'application avant activation.

---

### 🐧 Linux (universel systemd)

> Compatible avec : Ubuntu, Debian, Fedora, Arch, Mint, Pop!_OS, Rocky, Alma, openSUSE...
> Toutes les commandes utilisent `systemctl`, `sysctl`, `ufw`, `ss`, `chmod` — communs à 95% des distros.

#### Toggle 1 — Firewall UFW

```bash
# ✅ ACTIVER (politique par défaut : bloquer entrant, autoriser sortant)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# ❌ DÉSACTIVER
sudo ufw disable

# 🔍 VÉRIFIER
sudo ufw status verbose
```

> **Note** : Si UFW n'est pas installé, la détection de la distro est nécessaire :
> `apt install ufw` (Debian/Ubuntu) | `dnf install ufw` (Fedora) | `pacman -S ufw` (Arch)

#### Toggle 2 — Paramètres réseau sécurisés (sysctl)

```bash
# ✅ ACTIVER
sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null <<EOF
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
sudo sysctl --system

# ❌ DÉSACTIVER
sudo rm /etc/sysctl.d/99-hardening.conf
sudo sysctl --system

# 🔍 VÉRIFIER
sysctl net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.send_redirects
```

> **Explication simple** : Empêche le PC d'accepter des instructions réseau frauduleuses
> (redirection de trafic, usurpation d'adresse, etc.)

#### Toggle 3 — Désactiver les services inutiles

```bash
# ✅ DÉSACTIVER (exemples courants — adapter selon la machine)
sudo systemctl disable --now cups       # Service d'impression (inutile sur serveur)
sudo systemctl disable --now avahi-daemon  # Découverte réseau (inutile si pas de Bonjour/AirPlay)

# ❌ RÉACTIVER
sudo systemctl enable --now cups
sudo systemctl enable --now avahi-daemon

# 🔍 VÉRIFIER
systemctl is-active cups avahi-daemon
```

> **Note** : Ne pas désactiver Bluetooth si l'utilisateur l'utilise.
> Prévoir une détection intelligente ou laisser l'utilisateur choisir les services à désactiver.

#### Toggle 4 — Permissions fichiers sensibles

```bash
# ✅ SÉCURISER
sudo chmod 600 /etc/shadow
sudo chmod 600 /etc/gshadow
sudo chmod 644 /etc/passwd
sudo chmod 700 /etc/ssh

# 🔍 VÉRIFIER
stat -c "%a %n" /etc/shadow /etc/gshadow /etc/passwd /etc/ssh
```

> Ces permissions sont normalement déjà correctes, mais certaines installations ou manipulations peuvent les altérer.

#### Toggle 5 — Fail2Ban pour SSH

```bash
# ✅ ACTIVER
# Installation (détection distro nécessaire)
# apt install fail2ban | dnf install fail2ban | pacman -S fail2ban
sudo systemctl enable --now fail2ban

# ❌ DÉSACTIVER
sudo systemctl disable --now fail2ban

# 🔍 VÉRIFIER
sudo fail2ban-client status sshd
```

> **Ce que ça fait** : Bannit temporairement les IP qui échouent à se connecter en SSH trop de fois.
> Protection contre le brute-force.

#### Toggle 6 — Mises à jour automatiques de sécurité

```bash
# Pour Debian/Ubuntu :
# ✅ ACTIVER
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# ❌ DÉSACTIVER
sudo dpkg-reconfigure unattended-upgrades  # et répondre "Non"

# Pour Fedora/RHEL :
# ✅ ACTIVER
sudo dnf install -y dnf-automatic
sudo systemctl enable --now dnf-automatic-install.timer

# ❌ DÉSACTIVER
sudo systemctl disable --now dnf-automatic-install.timer

# 🔍 VÉRIFIER (Debian/Ubuntu)
systemctl is-active unattended-upgrades
# 🔍 VÉRIFIER (Fedora/RHEL)
systemctl is-active dnf-automatic-install.timer
```

#### Toggle 7 — Désactiver le login root par mot de passe

```bash
# ✅ DÉSACTIVER (le root reste accessible via sudo)
sudo passwd -l root

# ❌ RÉACTIVER
sudo passwd -u root

# 🔍 VÉRIFIER (LK = locked = sécurisé)
sudo passwd -S root
```

---

### 🍎 macOS

#### Toggle 1 — Firewall applicatif

```bash
# ✅ ACTIVER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# ❌ DÉSACTIVER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off

# 🔍 VÉRIFIER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

#### Toggle 2 — Mode furtif (Stealth Mode)

```bash
# ✅ ACTIVER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# ❌ DÉSACTIVER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off

# 🔍 VÉRIFIER
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
```

> **Ce que ça fait** : Le Mac ne répond plus aux requêtes ICMP (ping) et aux scans de ports.
> La machine devient "invisible" sur le réseau.

#### Toggle 3 — FileVault (chiffrement disque)

```bash
# ✅ ACTIVER
sudo fdesetup enable

# ❌ DÉSACTIVER
sudo fdesetup disable

# 🔍 VÉRIFIER
fdesetup status
```

> **Attention** : Comme BitLocker, FileVault génère une clé de récupération.
> Prévoir un message d'avertissement dans l'application.

#### Toggle 4 — Désactiver les services de partage

```bash
# ✅ DÉSACTIVER
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null    # Partage de fichiers
sudo systemsetup -setremotelogin off   # SSH distant (si géré par l'app, ignorer)

# ❌ RÉACTIVER
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist
sudo systemsetup -setremotelogin on

# 🔍 VÉRIFIER
sudo systemsetup -getremotelogin
```

> **Note** : Ne pas désactiver Remote Login si l'application l'utilise pour SSH.
> Ne proposer que le partage de fichiers SMB dans ce cas.

#### Toggle 5 — Mises à jour automatiques

```bash
# ✅ ACTIVER
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

# ❌ DÉSACTIVER
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false

# 🔍 VÉRIFIER
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled
```

#### Toggle 6 — Saisie clavier sécurisée (Terminal)

```bash
# ✅ ACTIVER
defaults write com.apple.terminal SecureKeyboardEntry -bool true

# ❌ DÉSACTIVER
defaults write com.apple.terminal SecureKeyboardEntry -bool false

# 🔍 VÉRIFIER
defaults read com.apple.terminal SecureKeyboardEntry
```

> **Ce que ça fait** : Empêche les autres applications d'intercepter ce que vous tapez dans le Terminal
> (keylogger protection).

#### Toggle 7 — Gatekeeper (blocage apps non signées)

```bash
# ✅ ACTIVER
sudo spctl --master-enable

# ❌ DÉSACTIVER
sudo spctl --master-disable

# 🔍 VÉRIFIER
spctl --status
```

#### Toggle 8 — Verrouillage écran automatique

```bash
# ✅ ACTIVER (demande mot de passe immédiatement après veille)
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# ❌ DÉSACTIVER (délai de 5 secondes)
defaults write com.apple.screensaver askForPasswordDelay -int 5

# 🔍 VÉRIFIER
defaults read com.apple.screensaver askForPassword
defaults read com.apple.screensaver askForPasswordDelay
```

---

---

## BLOC 2 — Checkup Système (bouton unique)

> **Fonctionnement** : L'utilisateur clique sur un bouton → le script s'exécute → les résultats s'affichent sous forme de résumé avec des icônes ✅ ⚠️ ❌

> **Principe** : Tout est en **lecture seule**. Le checkup ne modifie rien, il constate.

---

### 🪟 Windows 11 — Commandes de checkup

```powershell
# 1. FIREWALL — Actif ou non
Get-NetFirewallProfile | Select Name, Enabled
# Attendu : Enabled = True pour les 3 profils

# 2. MISES À JOUR EN ATTENTE
# Nécessite le module PSWindowsUpdate ou :
Get-HotFix | Sort-Object InstalledOn -Descending | Select -First 5
# + Comparer la date du dernier patch avec la date actuelle

# 3. BITLOCKER — Chiffrement actif
Get-BitLockerVolume -MountPoint "C:" | Select VolumeStatus, EncryptionPercentage
# Attendu : FullyEncrypted

# 4. WINDOWS DEFENDER — Signatures à jour
Get-MpComputerStatus | Select AntivirusSignatureLastUpdated, AntivirusEnabled, RealTimeProtectionEnabled
# Vérifier que la date < 7 jours

# 5. SCAN RAPIDE MALWARE (Windows Defender)
Start-MpScan -ScanType QuickScan
# Puis récupérer les résultats :
Get-MpThreatDetection | Select ThreatName, ActionSuccess

# 6. PROGRAMMES AU DÉMARRAGE
Get-CimInstance Win32_StartupCommand | Select Name, Command, Location
# Afficher la liste pour que l'utilisateur vérifie

# 7. TÂCHES PLANIFIÉES SUSPECTES
Get-ScheduledTask | Where-Object {$_.State -eq "Ready" -and $_.TaskPath -notlike "\Microsoft\*"} | Select TaskName, TaskPath, State
# Les tâches hors de \Microsoft\ sont celles installées par des tiers

# 8. CONNEXIONS RÉSEAU ACTIVES
Get-NetTCPConnection -State Established | Select LocalPort, RemoteAddress, RemotePort, OwningProcess | Sort RemoteAddress
# Afficher pour que l'utilisateur repère des IP inconnues

# 9. TENTATIVES DE CONNEXION ÉCHOUÉES (dernières 24h)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue | Measure-Object | Select Count
# Id 4625 = échec de connexion

# 10. COMPTES UTILISATEURS
Get-LocalUser | Select Name, Enabled, LastLogon
# Vérifier qu'il n'y a pas de comptes inconnus activés

# 11. ESPACE DISQUE
Get-PSDrive -PSProvider FileSystem | Select Name, @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}}, @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}}
# Alerter si < 10% restant

# 12. SMBv1 DÉSACTIVÉ
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol | Select State
# Attendu : Disabled
```

---

### 🐧 Linux — Commandes de checkup

```bash
# 1. FIREWALL — Actif ou non
sudo ufw status | head -1
# Attendu : "Status: active"

# 2. MISES À JOUR EN ATTENTE
# Debian/Ubuntu :
apt list --upgradable 2>/dev/null | grep -c upgradable
# Fedora :
dnf check-update --quiet 2>/dev/null | wc -l

# 3. CHIFFREMENT DISQUE (LUKS)
lsblk -o NAME,FSTYPE,MOUNTPOINT | grep -i crypt
# Si résultat vide = pas de chiffrement détecté

# 4. PARAMÈTRES RÉSEAU SÉCURISÉS
sysctl net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.send_redirects net.ipv4.conf.all.accept_source_route
# Attendu : tout à 0

# 5. ROOTKIT CHECK (si rkhunter installé)
# Installation si absent : apt install rkhunter | dnf install rkhunter
sudo rkhunter --check --skip-keypress --report-warnings-only 2>/dev/null
# Afficher uniquement les warnings

# 6. CRON JOBS SUSPECTS (tous les utilisateurs)
for user in $(cut -f1 -d: /etc/passwd); do
  crontab -l -u "$user" 2>/dev/null | grep -v "^#"
done
# + vérifier /etc/cron.d/ et /etc/crontab

# 7. CONNEXIONS RÉSEAU ACTIVES
ss -tunap | grep ESTAB
# Afficher les connexions établies avec les processus associés

# 8. TENTATIVES DE CONNEXION ÉCHOUÉES
journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" 2>/dev/null | grep -c "Failed password"
# Nombre de tentatives SSH échouées dans les dernières 24h

# 9. COMPTES UTILISATEURS AVEC SHELL
awk -F: '$7 !~ /(nologin|false)/ {print $1}' /etc/passwd
# Liste les comptes qui peuvent se connecter

# 10. PERMISSIONS FICHIERS SENSIBLES
stat -c "%a %n" /etc/shadow /etc/gshadow /etc/ssh/sshd_config 2>/dev/null
# Attendu : 600 pour shadow/gshadow, 600 ou 644 pour sshd_config

# 11. ESPACE DISQUE
df -h / | awk 'NR==2 {print $5}'
# Alerter si > 90%

# 12. FAIL2BAN ACTIF (si installé)
sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned"
# Afficher le nombre d'IP bannies
```

---

### 🍎 macOS — Commandes de checkup

```bash
# 1. FIREWALL — Actif ou non
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
# Attendu : "Firewall is enabled"

# 2. MODE FURTIF
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
# Attendu : "Stealth mode enabled"

# 3. FILEVAULT — Chiffrement actif
fdesetup status
# Attendu : "FileVault is On"

# 4. XPROTECT — Antimalware à jour
system_profiler SPInstallHistoryDataType | grep -A 2 "XProtect"
# Vérifier la date de dernière mise à jour

# 5. GATEKEEPER
spctl --status
# Attendu : "assessments enabled"

# 6. LAUNCH AGENTS / DAEMONS SUSPECTS
ls ~/Library/LaunchAgents/ 2>/dev/null
ls /Library/LaunchAgents/ 2>/dev/null
ls /Library/LaunchDaemons/ 2>/dev/null
# Les fichiers qui ne commencent pas par "com.apple." sont des tiers → à vérifier

# 7. CONNEXIONS RÉSEAU ACTIVES
lsof -i -P | grep ESTABLISHED
# Afficher les connexions établies avec les processus

# 8. TENTATIVES DE CONNEXION ÉCHOUÉES
log show --predicate 'eventMessage contains "authentication failure"' --last 24h 2>/dev/null | wc -l

# 9. COMPTES UTILISATEURS
dscl . -list /Users | grep -v "^_"
# Les comptes commençant par _ sont des comptes système

# 10. MISES À JOUR EN ATTENTE
softwareupdate -l 2>/dev/null
# Liste les mises à jour disponibles

# 11. ESPACE DISQUE
df -h / | awk 'NR==2 {print $5}'
# Alerter si > 90%

# 12. SAISIE CLAVIER SÉCURISÉE
defaults read com.apple.terminal SecureKeyboardEntry 2>/dev/null
# Attendu : 1
```

---

---

## Format d'affichage du résumé Checkup

> Suggestion pour l'affichage dans l'application.

```
╔══════════════════════════════════════════════════════════╗
║                  🛡️ CHECKUP SYSTÈME                     ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Firewall                    ✅ Actif                    ║
║  Mises à jour                ⚠️  3 en attente            ║
║  Chiffrement disque          ❌ Désactivé                ║
║  Antivirus / signatures      ✅ À jour (il y a 2 jours) ║
║  Scan rapide malware         ✅ Aucune menace            ║
║  Programmes au démarrage     ⚠️  2 éléments à vérifier   ║
║  Tâches planifiées           ✅ RAS                      ║
║  Connexions réseau           ⚠️  1 connexion inconnue    ║
║  Tentatives de connexion     ✅ 0 échecs (24h)           ║
║  Comptes utilisateurs        ✅ 2 comptes (tous connus)  ║
║  Espace disque               ✅ 45% utilisé              ║
║  Paramètres réseau           ✅ Sécurisés                ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║  Score : 10/12  —  Bon état général                      ║
║                                                          ║
║  💡 Recommandation : Activez le chiffrement disque       ║
║     et installez les mises à jour en attente.            ║
╚══════════════════════════════════════════════════════════╝
```

### Logique du score

| Icône | Signification | Points |
|-------|--------------|--------|
| ✅ | OK / Conforme | 1 point |
| ⚠️ | Attention / À vérifier manuellement | 0.5 point |
| ❌ | Problème détecté / Non conforme | 0 point |

**Interprétation :**
- **11-12 / 12** → 🟢 Excellent
- **8-10 / 12** → 🟡 Bon, quelques améliorations possibles
- **5-7 / 12** → 🟠 Moyen, actions recommandées
- **< 5 / 12** → 🔴 Critique, actions urgentes

---

---

## Conseils d'implémentation

### Exécution des commandes

- Toutes les commandes nécessitent des **droits administrateur** (sudo / Exécuter en tant qu'administrateur)
- L'application doit vérifier les droits avant d'exécuter les commandes
- Prévoir un message si les droits sont insuffisants

### Toggles — UX recommandée

- Afficher l'**état actuel** de chaque option au chargement de la page (via la commande 🔍 VÉRIFIER)
- Un toggle grisé si la fonctionnalité n'est pas disponible (ex : BitLocker sans TPM)
- Une **infobulle** courte pour expliquer chaque option en langage simple

### Checkup — UX recommandée

- Afficher une **barre de progression** pendant l'analyse
- Le scan malware (Windows Defender / rkhunter) peut prendre **1 à 5 minutes**
- Prévoir un bouton "Scan rapide" (sans malware scan) et "Scan complet" (avec)
- Les éléments ⚠️ devraient être **cliquables** pour afficher le détail

### Sécurité de l'application elle-même

- Ne jamais stocker de résultats de checkup en clair sur le disque
- Les commandes sont exécutées localement, rien n'est envoyé sur le réseau
- Logger les actions de hardening pour permettre un rollback si besoin

### Détection de l'OS

```
Windows → Vérifier via la variable d'environnement ou la commande `ver`
Linux   → Vérifier la présence de /etc/os-release et lire ID= pour la distro
macOS   → Vérifier via `sw_vers` ou `uname -s` == "Darwin"
```

### Détection du gestionnaire de paquets Linux (pour fail2ban, rkhunter, ufw)

```bash
if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
fi
```
