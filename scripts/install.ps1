# ──────────────────────────────────────────────────────────
#  Chill — Script d'installation
#  Windows (PowerShell)
#
#  Usage :
#    irm https://raw.githubusercontent.com/Kevin-hDev/ChillApp/main/scripts/install.ps1 | iex
#
#  Variables optionnelles :
#    $env:CHILL_DIR  — Dossier d'installation (défaut : %LOCALAPPDATA%\Chill)
# ──────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

$GITHUB_REPO = "Kevin-hDev/ChillApp"
$CHILL_DIR = if ($env:CHILL_DIR) { $env:CHILL_DIR } else { "$env:LOCALAPPDATA\Chill" }

# ── Helpers ───────────────────────────────────────────────

function Write-Ok   { param([string]$msg) Write-Host "  " -NoNewline; Write-Host "✓" -ForegroundColor Green -NoNewline; Write-Host " $msg" }
function Write-Warn { param([string]$msg) Write-Host "  " -NoNewline; Write-Host "!" -ForegroundColor Yellow -NoNewline; Write-Host " $msg" }
function Write-Err  { param([string]$msg) Write-Host "  " -NoNewline; Write-Host "✗" -ForegroundColor Red -NoNewline; Write-Host " $msg" }
function Write-Step { param([string]$msg) Write-Host "  " -NoNewline; Write-Host "→" -ForegroundColor Cyan -NoNewline; Write-Host " $msg" }

# ── Détection de l'architecture ──────────────────────────

function Get-Arch {
    if ([Environment]::Is64BitOperatingSystem) { return "x64" }
    Write-Err "Architecture 32-bit non supportée. Chill nécessite Windows 64-bit."
    exit 1
}

# ── Téléchargement depuis GitHub Releases ─────────────────

function Get-DownloadUrl {
    param([string]$Arch)

    $assetName = "chill-windows-$Arch.zip"
    Write-Step "Recherche de la dernière version..."

    try {
        $release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
            -Headers @{ "User-Agent" = "Chill-Installer" }
    } catch {
        Write-Err "Impossible de contacter GitHub. Vérifie ta connexion internet."
        exit 1
    }

    $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        Write-Err "Aucune release trouvée pour $assetName"
        Write-Step "Vérifie les releases disponibles : https://github.com/$GITHUB_REPO/releases"
        exit 1
    }

    # Validation de sécurité : URL doit être depuis GitHub
    $url = $asset.browser_download_url
    if ($url -notmatch '^https://(github\.com|objects\.githubusercontent\.com)/') {
        Write-Err "URL de téléchargement suspecte : $url"
        exit 1
    }

    return @{ Url = $url; Version = $release.tag_name }
}

# ── Installation ──────────────────────────────────────────

function Install-Chill {
    param(
        [string]$DownloadUrl,
        [string]$Version
    )

    # Dossier temporaire
    $tmpDir = Join-Path $env:TEMP "chill-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        $zipPath = Join-Path $tmpDir "chill.zip"

        Write-Step "Téléchargement de Chill $Version..."
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
        } catch {
            Write-Err "Échec du téléchargement : $_"
            exit 1
        }

        Write-Step "Vérification de l'archive..."
        if (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -eq 0) {
            Write-Err "L'archive téléchargée est vide ou corrompue."
            exit 1
        }

        Write-Step "Extraction..."
        try {
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
        } catch {
            Write-Err "Échec de l'extraction : $_"
            exit 1
        }

        # Trouver le dossier extrait
        $extractedDir = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if (-not $extractedDir) {
            Write-Err "Structure d'archive inattendue."
            exit 1
        }

        # Arrêter Chill s'il tourne
        $appProcess = Get-Process -Name "chill_app" -ErrorAction SilentlyContinue
        if ($appProcess) {
            Write-Step "Arrêt de Chill en cours..."
            Stop-Process -Name "chill_app" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }

        # Installer dans CHILL_DIR
        Write-Step "Installation dans $CHILL_DIR..."
        New-Item -ItemType Directory -Path $CHILL_DIR -Force | Out-Null
        Copy-Item -Path "$($extractedDir.FullName)\*" -Destination $CHILL_DIR -Recurse -Force

    } finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Configuration du PATH ─────────────────────────────────

function Add-ToPath {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($userPath -and $userPath.Split(";") -contains $CHILL_DIR) {
        return  # Déjà dans le PATH
    }

    $newPath = if ($userPath) { "$CHILL_DIR;$userPath" } else { $CHILL_DIR }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$CHILL_DIR;$env:Path"
    Write-Ok "Chill ajouté au PATH utilisateur"
}

# ── Raccourcis ────────────────────────────────────────────

function Create-Shortcuts {
    $appBin = "$CHILL_DIR\chill_app.exe"

    if (-not (Test-Path $appBin)) {
        return
    }

    $wshell = New-Object -ComObject WScript.Shell

    # Raccourci dans le Menu Démarrer
    try {
        $startMenuDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        $startMenuLink = "$startMenuDir\Chill.lnk"
        New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
        $shortcut = $wshell.CreateShortcut($startMenuLink)
        $shortcut.TargetPath = $appBin
        $shortcut.WorkingDirectory = $CHILL_DIR
        $shortcut.Description = "Chill — Configuration SSH, WoL et Tailscale"
        $shortcut.Save()
        Write-Ok "Raccourci créé dans le Menu Démarrer"
    } catch {
        Write-Warn "Impossible de créer le raccourci Menu Démarrer"
    }

    # Raccourci sur le Bureau
    try {
        $desktopLink = Join-Path ([Environment]::GetFolderPath("Desktop")) "Chill.lnk"
        $shortcut = $wshell.CreateShortcut($desktopLink)
        $shortcut.TargetPath = $appBin
        $shortcut.WorkingDirectory = $CHILL_DIR
        $shortcut.Description = "Chill — Configuration SSH, WoL et Tailscale"
        $shortcut.Save()
        Write-Ok "Raccourci créé sur le Bureau"
    } catch {
        Write-Warn "Impossible de créer le raccourci Bureau"
    }
}

# ── Main ──────────────────────────────────────────────────

Write-Host ""
Write-Host "  Installation de Chill" -ForegroundColor White
Write-Host ""

$arch = Get-Arch
$result = Get-DownloadUrl -Arch $arch

Write-Step "OS : Windows | Architecture : $arch | Version : $($result.Version)"

Install-Chill -DownloadUrl $result.Url -Version $result.Version

Add-ToPath

Create-Shortcuts

Write-Host ""
Write-Host "  Chill installé avec succès !" -ForegroundColor Green
Write-Host ""
Write-Host "  Commandes disponibles :"
Write-Host ""
Write-Host "    " -NoNewline; Write-Host "chill status" -ForegroundColor Cyan -NoNewline; Write-Host "    — État de SSH, WoL, Tailscale"
Write-Host "    " -NoNewline; Write-Host "chill info" -ForegroundColor Cyan -NoNewline; Write-Host "      — Ton IP, MAC, hostname"
Write-Host "    " -NoNewline; Write-Host "chill start" -ForegroundColor Cyan -NoNewline; Write-Host "     — Ouvrir l'application"
Write-Host "    " -NoNewline; Write-Host "chill doctor" -ForegroundColor Cyan -NoNewline; Write-Host "    — Diagnostic de l'installation"
Write-Host "    " -NoNewline; Write-Host "chill help" -ForegroundColor Cyan -NoNewline; Write-Host "      — Toutes les commandes"
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "!" -ForegroundColor Yellow -NoNewline
Write-Host " Ouvre un nouveau terminal PowerShell pour utiliser " -NoNewline
Write-Host "chill" -ForegroundColor White -NoNewline
Write-Host ""
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "→" -ForegroundColor Cyan -NoNewline
Write-Host " Lance l'app : " -NoNewline
Write-Host "chill start" -ForegroundColor White
Write-Host ""
