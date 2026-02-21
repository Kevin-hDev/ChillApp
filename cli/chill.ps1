# ──────────────────────────────────────────────────────────
#  Chill CLI — Commandes terminal pour gérer l'app Chill
#  Windows (PowerShell)
# ──────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$CHILL_DIR = if ($env:CHILL_DIR) { $env:CHILL_DIR } else { "$env:LOCALAPPDATA\Chill" }
$APP_BIN = "$CHILL_DIR\chill_app.exe"
$DAEMON_BIN = "$CHILL_DIR\chill-tailscale.exe"
$VERSION_FILE = "$CHILL_DIR\VERSION"
$PREFS_DIR = "$env:APPDATA\chill_app"
$GITHUB_REPO = "Kevin-hDev/ChillApp"

# ── Helpers ──────────────────────────────────────────────

function Write-Ok    { param([string]$msg) Write-Host "  ✓ " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn  { param([string]$msg) Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err   { param([string]$msg) Write-Host "  ✗ " -ForegroundColor Red -NoNewline; Write-Host $msg }
function Write-Info  { param([string]$msg) Write-Host "  → " -ForegroundColor Cyan -NoNewline; Write-Host $msg }

function Test-ChillInstalled {
    if (-not (Test-Path $APP_BIN)) {
        Write-Err "Chill n'est pas installé dans $CHILL_DIR"
        Write-Info "Installe-le avec : irm https://raw.githubusercontent.com/Kevin-hDev/ChillApp/main/scripts/install.ps1 | iex"
        exit 1
    }
}

# ── Commandes ────────────────────────────────────────────

function Invoke-Version {
    if (Test-Path $VERSION_FILE) {
        $ver = Get-Content $VERSION_FILE -Raw
        Write-Host "  Chill v$($ver.Trim())" -ForegroundColor White
    } else {
        Write-Host "  Chill " -ForegroundColor White -NoNewline
        Write-Host "(version inconnue)" -ForegroundColor DarkGray
    }
}

function Invoke-Help {
    Write-Host ""
    Write-Host "  Chill" -ForegroundColor White -NoNewline
    Write-Host " — Hub de configuration pour ChillShell"
    Write-Host ""
    Write-Host "  Usage :" -ForegroundColor White
    Write-Host "    chill <commande> [options]"
    Write-Host ""
    Write-Host "  Commandes :" -ForegroundColor White
    $cmds = @(
        @("version",          "Affiche la version installée"),
        @("status",           "Résumé SSH / WoL / Tailscale / sécurité"),
        @("info",             "Affiche IP, hostname, adresse MAC"),
        @("start",            "Lance l'application graphique"),
        @("stop",             "Ferme l'application"),
        @("update",           "Met à jour vers la dernière version"),
        @("uninstall",        "Désinstalle Chill proprement"),
        @("autostart on|off", "Active/désactive le lancement au démarrage"),
        @("doctor",           "Diagnostic complet de l'installation"),
        @("security",         "Checkup de sécurité du système"),
        @("logs",             "Affiche les derniers logs"),
        @("reset",            "Remet tous les réglages à zéro"),
        @("help",             "Affiche cette aide")
    )
    foreach ($c in $cmds) {
        Write-Host "    " -NoNewline
        Write-Host ("{0,-20}" -f $c[0]) -ForegroundColor Cyan -NoNewline
        Write-Host $c[1]
    }
    Write-Host ""
}

function Invoke-Status {
    Test-ChillInstalled

    Write-Host ""
    Write-Host "  État des services" -ForegroundColor White
    Write-Host ""

    # SSH (OpenSSH Server)
    try {
        $sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue
        if ($sshService -and $sshService.Status -eq "Running") {
            Write-Ok "SSH              actif"
        } elseif ($sshService) {
            Write-Err "SSH              installé mais arrêté"
        } else {
            Write-Err "SSH              non installé"
        }
    } catch {
        Write-Err "SSH              non installé"
    }

    # WoL (vérifie via adaptateur réseau)
    try {
        $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        if ($adapter) {
            $wol = Get-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Wake on*" -ErrorAction SilentlyContinue
            if ($wol -and $wol.DisplayValue -match "Enabled|Magic Packet") {
                Write-Ok "Wake-on-LAN      actif"
            } else {
                Write-Warn "Wake-on-LAN      inactif"
            }
        } else {
            Write-Warn "Wake-on-LAN      aucun adaptateur trouvé"
        }
    } catch {
        Write-Warn "Wake-on-LAN      impossible à vérifier"
    }

    # Tailscale
    $tsCmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tsCmd) {
        try {
            $tsStatus = & tailscale status 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Tailscale        connecté"
            } else {
                Write-Warn "Tailscale        déconnecté"
            }
        } catch {
            Write-Warn "Tailscale        déconnecté"
        }
    } else {
        Write-Err "Tailscale        non installé"
    }

    # Firewall Windows
    try {
        $fw = Get-NetFirewallProfile -Profile Domain, Public, Private -ErrorAction SilentlyContinue
        $allEnabled = ($fw | Where-Object { $_.Enabled -eq $true }).Count -eq $fw.Count
        if ($allEnabled) {
            Write-Ok "Firewall         actif (tous les profils)"
        } else {
            $enabledCount = ($fw | Where-Object { $_.Enabled -eq $true }).Count
            Write-Warn "Firewall         partiellement actif ($enabledCount/$($fw.Count) profils)"
        }
    } catch {
        Write-Warn "Firewall         impossible à vérifier"
    }

    # App en cours
    $appProcess = Get-Process -Name "chill_app" -ErrorAction SilentlyContinue
    if ($appProcess) {
        Write-Ok "App Chill        en cours d'exécution"
    } else {
        Write-Info "App Chill        arrêtée"
    }

    Write-Host ""
}

function Invoke-Info {
    Write-Host ""
    Write-Host "  Infos de connexion" -ForegroundColor White
    Write-Host ""

    # Hostname
    Write-Host "  " -NoNewline
    Write-Host "Hostname :      " -ForegroundColor DarkGray -NoNewline
    Write-Host $env:COMPUTERNAME

    # Username
    Write-Host "  " -NoNewline
    Write-Host "Utilisateur :   " -ForegroundColor DarkGray -NoNewline
    Write-Host $env:USERNAME

    # IP et MAC via Get-NetAdapter + Get-NetIPAddress
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        foreach ($adapter in $adapters) {
            $ipInfo = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ipInfo) {
                $type = if ($adapter.Name -match "Wi-Fi|Wireless|WLAN") { "Wi-Fi" } else { "Ethernet" }
                Write-Host "  " -NoNewline
                Write-Host ("IP {0} :     " -f $type) -ForegroundColor DarkGray -NoNewline
                Write-Host "$($ipInfo.IPAddress) ($($adapter.Name))"
                Write-Host "  " -NoNewline
                Write-Host "MAC :           " -ForegroundColor DarkGray -NoNewline
                Write-Host $adapter.MacAddress
            }
        }
    } catch {
        Write-Warn "Impossible de récupérer les infos réseau"
    }

    # IP Tailscale
    $tsCmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tsCmd) {
        try {
            $tsIp = & tailscale ip -4 2>&1
            if ($LASTEXITCODE -eq 0 -and $tsIp) {
                Write-Host "  " -NoNewline
                Write-Host "IP Tailscale :  " -ForegroundColor DarkGray -NoNewline
                Write-Host $tsIp.Trim()
            }
        } catch {}
    }

    Write-Host ""
}

function Invoke-Start {
    Test-ChillInstalled
    $appProcess = Get-Process -Name "chill_app" -ErrorAction SilentlyContinue
    if ($appProcess) {
        Write-Warn "Chill est déjà en cours d'exécution"
        return
    }
    Start-Process -FilePath $APP_BIN -WindowStyle Normal
    Write-Ok "Chill lancé"
}

function Invoke-Stop {
    $appProcess = Get-Process -Name "chill_app" -ErrorAction SilentlyContinue
    if ($appProcess) {
        Stop-Process -Name "chill_app" -Force
        Write-Ok "Chill arrêté"
    } else {
        Write-Info "Chill n'est pas en cours d'exécution"
    }
}

function Invoke-Update {
    Test-ChillInstalled
    Write-Info "Recherche de la dernière version..."

    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $assetName = "chill-windows-${arch}.zip"

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$GITHUB_REPO/releases/latest" -Headers @{ "User-Agent" = "Chill-CLI" }
    } catch {
        Write-Err "Impossible de contacter GitHub"
        exit 1
    }

    $asset = $release.assets | Where-Object { $_.name -eq $assetName }
    if (-not $asset) {
        Write-Err "Aucune release trouvée pour $assetName"
        exit 1
    }

    $currentVersion = if (Test-Path $VERSION_FILE) { (Get-Content $VERSION_FILE -Raw).Trim() } else { "0.0.0" }

    # Stopper l'app si elle tourne
    $appProcess = Get-Process -Name "chill_app" -ErrorAction SilentlyContinue
    if ($appProcess) {
        Write-Info "Arrêt de l'app..."
        Stop-Process -Name "chill_app" -Force
        Start-Sleep -Seconds 1
    }

    $tmpDir = Join-Path $env:TEMP "chill-update-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $zipPath = Join-Path $tmpDir "chill.zip"

    Write-Info "Téléchargement..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing

    Write-Info "Extraction..."
    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force

    # Trouver le dossier extrait
    $extractedDir = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
    if (-not $extractedDir) {
        $extractedDir = Get-Item $tmpDir
    }

    # Copier les fichiers
    Copy-Item -Path "$($extractedDir.FullName)\*" -Destination $CHILL_DIR -Recurse -Force

    Remove-Item -Path $tmpDir -Recurse -Force

    $newVersion = if (Test-Path $VERSION_FILE) { (Get-Content $VERSION_FILE -Raw).Trim() } else { "?" }
    Write-Ok "Mis à jour : v$currentVersion → v$newVersion"
}

function Invoke-Uninstall {
    Test-ChillInstalled
    Write-Host ""
    Write-Host "  Désinstaller Chill ?" -ForegroundColor Yellow
    Write-Host "  Cela supprimera :"
    Write-Host "    - L'application ($CHILL_DIR)"
    Write-Host "    - La commande chill du PATH"
    Write-Host "    - Les raccourcis (Bureau + Menu Démarrer)"
    Write-Host "    - Les préférences ($PREFS_DIR)"
    Write-Host ""
    $confirm = Read-Host "  Confirmer ? (o/N)"
    if ($confirm -notmatch '^[oOyY]$') {
        Write-Info "Annulé"
        return
    }

    # Stopper l'app
    Stop-Process -Name "chill_app" -Force -ErrorAction SilentlyContinue

    # Supprimer les fichiers
    if (Test-Path $CHILL_DIR) { Remove-Item -Path $CHILL_DIR -Recurse -Force }
    if (Test-Path $PREFS_DIR) { Remove-Item -Path $PREFS_DIR -Recurse -Force }

    # Supprimer les raccourcis
    $startMenuLink = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Chill.lnk"
    if (Test-Path $startMenuLink) { Remove-Item -Path $startMenuLink -Force }
    $desktopLink = Join-Path ([Environment]::GetFolderPath("Desktop")) "Chill.lnk"
    if (Test-Path $desktopLink) { Remove-Item -Path $desktopLink -Force }

    # Retirer du PATH
    try {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -and $userPath.Contains($CHILL_DIR)) {
            $newPath = ($userPath.Split(";") | Where-Object { $_ -ne $CHILL_DIR }) -join ";"
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        }
    } catch {}

    Write-Ok "Chill désinstallé"
}

function Invoke-Autostart {
    param([string]$Action)
    Test-ChillInstalled

    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

    if ($Action -eq "on") {
        Set-ItemProperty -Path $regPath -Name "Chill" -Value "`"$APP_BIN`""
        Write-Ok "Lancement au démarrage activé"
    }
    elseif ($Action -eq "off") {
        Remove-ItemProperty -Path $regPath -Name "Chill" -ErrorAction SilentlyContinue
        Write-Ok "Lancement au démarrage désactivé"
    }
    else {
        Write-Err "Usage : chill autostart on|off"
        exit 1
    }
}

function Invoke-Doctor {
    Test-ChillInstalled
    $issues = 0

    Write-Host ""
    Write-Host "  Diagnostic Chill" -ForegroundColor White
    Write-Host ""

    # Binaire app
    if (Test-Path $APP_BIN) {
        Write-Ok "Binaire app        $APP_BIN"
    } else {
        Write-Err "Binaire app        introuvable"
        $issues++
    }

    # Daemon Tailscale
    if (Test-Path $DAEMON_BIN) {
        Write-Ok "Daemon Tailscale   $DAEMON_BIN"
    } else {
        Write-Warn "Daemon Tailscale   introuvable"
        $issues++
    }

    # Version
    if (Test-Path $VERSION_FILE) {
        $ver = (Get-Content $VERSION_FILE -Raw).Trim()
        Write-Ok "Version            v$ver"
    } else {
        Write-Warn "Fichier VERSION    introuvable"
        $issues++
    }

    # CLI dans le PATH
    $cliInPath = Get-Command chill -ErrorAction SilentlyContinue
    if ($cliInPath) {
        Write-Ok "CLI dans le PATH   $($cliInPath.Source)"
    } else {
        Write-Err "CLI pas dans le PATH"
        $issues++
    }

    # Tailscale installé
    $tsCmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tsCmd) {
        try {
            $tsVer = & tailscale version 2>&1 | Select-Object -First 1
            Write-Ok "Tailscale          $tsVer"
        } catch {
            Write-Ok "Tailscale          installé"
        }
    } else {
        Write-Warn "Tailscale          non installé"
    }

    # Raccourci Menu Démarrer
    $startMenuLink = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Chill.lnk"
    if (Test-Path $startMenuLink) {
        Write-Ok "Raccourci          Menu Démarrer"
    } else {
        Write-Warn "Raccourci          non créé"
    }

    # Autostart
    try {
        $autostart = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Chill" -ErrorAction SilentlyContinue
        if ($autostart) {
            Write-Ok "Démarrage auto     activé"
        } else {
            Write-Info "Démarrage auto     désactivé"
        }
    } catch {
        Write-Info "Démarrage auto     désactivé"
    }

    # Préférences
    if (Test-Path $PREFS_DIR) {
        Write-Ok "Préférences        $PREFS_DIR"
    } else {
        Write-Info "Préférences        aucune (premier lancement)"
    }

    Write-Host ""
    if ($issues -eq 0) {
        Write-Host "  Tout est en ordre !" -ForegroundColor Green
    } else {
        Write-Host "  $issues problème(s) détecté(s)" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Invoke-Security {
    Write-Host ""
    Write-Host "  Checkup sécurité" -ForegroundColor White
    Write-Host ""

    # Firewall
    try {
        $fw = Get-NetFirewallProfile -Profile Domain, Public, Private -ErrorAction SilentlyContinue
        $allEnabled = ($fw | Where-Object { $_.Enabled -eq $true }).Count -eq $fw.Count
        if ($allEnabled) {
            Write-Ok "Firewall Windows      actif (tous les profils)"
        } else {
            Write-Err "Firewall Windows      partiellement actif"
        }
    } catch {
        Write-Warn "Firewall Windows      impossible à vérifier"
    }

    # RDP (Bureau à distance)
    try {
        $rdp = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
        if ($rdp -and $rdp.fDenyTSConnections -eq 1) {
            Write-Ok "Bureau à distance     désactivé"
        } else {
            Write-Warn "Bureau à distance     activé (risque si pas sécurisé)"
        }
    } catch {
        Write-Warn "Bureau à distance     impossible à vérifier"
    }

    # SMBv1 (protocole obsolète)
    try {
        $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
        if ($smb1 -and $smb1.State -eq "Disabled") {
            Write-Ok "SMBv1                 désactivé"
        } elseif ($smb1 -and $smb1.State -eq "Enabled") {
            Write-Err "SMBv1                 activé (protocole obsolète !)"
        } else {
            Write-Info "SMBv1                 impossible à vérifier"
        }
    } catch {
        Write-Info "SMBv1                 impossible à vérifier (nécessite admin)"
    }

    # Windows Update
    try {
        $au = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -ErrorAction SilentlyContinue
        if ($au -and $au.AUOptions -ge 3) {
            Write-Ok "Mises à jour auto     activées"
        } else {
            Write-Warn "Mises à jour auto     à vérifier"
        }
    } catch {
        Write-Warn "Mises à jour auto     impossible à vérifier"
    }

    # UAC
    try {
        $uac = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue
        if ($uac -and $uac.EnableLUA -eq 1) {
            Write-Ok "UAC                   activé"
        } else {
            Write-Err "UAC                   désactivé"
        }
    } catch {
        Write-Warn "UAC                   impossible à vérifier"
    }

    # Windows Defender
    try {
        $defender = Get-MpPreference -ErrorAction SilentlyContinue
        if ($defender -and -not $defender.DisableRealtimeMonitoring) {
            Write-Ok "Windows Defender      actif (temps réel)"
        } else {
            Write-Err "Windows Defender      protection temps réel désactivée"
        }
    } catch {
        Write-Warn "Windows Defender      impossible à vérifier"
    }

    # SSH root/admin (vérifie si le service OpenSSH est configuré pour admin)
    try {
        $sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue
        if ($sshService) {
            $sshConfig = "$env:ProgramData\ssh\sshd_config"
            if (Test-Path $sshConfig) {
                $content = Get-Content $sshConfig -Raw
                if ($content -match "PermitRootLogin\s+no") {
                    Write-Ok "SSH root login        désactivé"
                } else {
                    Write-Warn "SSH root login        à vérifier"
                }
            }
        }
    } catch {}

    Write-Host ""
}

function Invoke-Logs {
    Write-Host ""
    Write-Info "L'app Chill n'écrit pas de logs système pour le moment"
    Write-Host ""

    # Tenter de lire l'Event Viewer pour les erreurs liées à chill
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = "Application"; Level = 2; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 10 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "chill" }
        if ($events) {
            Write-Host "  Erreurs récentes liées à Chill :" -ForegroundColor Yellow
            foreach ($ev in $events) {
                Write-Host "    [$($ev.TimeCreated.ToString('dd/MM HH:mm'))] $($ev.Message.Substring(0, [Math]::Min(100, $ev.Message.Length)))"
            }
            Write-Host ""
        }
    } catch {}
}

function Invoke-Reset {
    Write-Host ""
    Write-Host "  Remettre tous les réglages à zéro ?" -ForegroundColor Yellow
    Write-Host "  Cela supprimera : thème, langue, PIN, onboarding"
    Write-Host ""
    $confirm = Read-Host "  Confirmer ? (o/N)"
    if ($confirm -notmatch '^[oOyY]$') {
        Write-Info "Annulé"
        return
    }

    if (Test-Path $PREFS_DIR) {
        Remove-Item -Path $PREFS_DIR -Recurse -Force
    }
    Write-Ok "Réglages remis à zéro (prendront effet au prochain lancement)"
}

# ── Main ─────────────────────────────────────────────────

$command = if ($args.Count -ge 1) { $args[0] } else { "help" }
$subArgs = if ($args.Count -ge 2) { $args[1..($args.Count - 1)] } else { @() }

switch ($command) {
    "version"    { Invoke-Version }
    "status"     { Invoke-Status }
    "info"       { Invoke-Info }
    "start"      { Invoke-Start }
    "stop"       { Invoke-Stop }
    "update"     { Invoke-Update }
    "uninstall"  { Invoke-Uninstall }
    "autostart"  { Invoke-Autostart -Action ($subArgs | Select-Object -First 1) }
    "doctor"     { Invoke-Doctor }
    "security"   { Invoke-Security }
    "logs"       { Invoke-Logs }
    "reset"      { Invoke-Reset }
    { $_ -in "help", "--help", "-h" } { Invoke-Help }
    default {
        Write-Err "Commande inconnue : $command"
        Invoke-Help
        exit 1
    }
}
