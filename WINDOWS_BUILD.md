# Build Windows — Chill v1.0.0

## Contexte

ChillApp est une app desktop Flutter (Windows/Linux/macOS) qui permet de configurer SSH, Wake-on-LAN et Tailscale.

Le build Linux est **déjà fait et uploadé** sur la GitHub Release v1.0.0 :
- ✅ `chill-linux-x64.tar.gz` — déjà sur https://github.com/Kevin-hDev/ChillApp/releases/tag/v1.0.0

**Il manque le build Windows.** C'est l'objectif de ce PC.

---

## Ce qu'il faut faire ici (Windows)

### Étape 1 — Prérequis

Vérifier que Flutter est installé et fonctionne :
```powershell
flutter doctor
flutter --version
```

### Étape 2 — Builder l'app Windows

```powershell
cd C:\chemin\vers\ChillApp   # ou là où tu as cloné le repo
flutter pub get
flutter build windows --release
```

Le binaire sera dans : `build\windows\x64\runner\Release\`

### Étape 3 — Packager

```powershell
bash scripts/package-release.sh 1.0.0
```

> Si bash n'est pas dispo, utilise Git Bash ou WSL.

Ça produit : `dist\chill-windows-x64.zip`

### Étape 4 — Uploader à la release existante

```powershell
gh release upload v1.0.0 dist/chill-windows-x64.zip
```

> `gh` = GitHub CLI. Si pas installé : https://cli.github.com

### Étape 5 — Vérifier

Aller sur https://github.com/Kevin-hDev/ChillApp/releases/tag/v1.0.0
et vérifier que les deux fichiers sont là :
- `chill-linux-x64.tar.gz`
- `chill-windows-x64.zip`

### Étape 6 — Rendre le repo public

Sur GitHub → Settings → Danger Zone → Change visibility → Public

Ensuite les commandes d'installation fonctionnent :
```powershell
# Windows
irm https://raw.githubusercontent.com/Kevin-hDev/ChillApp/main/scripts/install.ps1 | iex
```
```bash
# Linux/macOS
curl -fsSL https://raw.githubusercontent.com/Kevin-hDev/ChillApp/main/scripts/install.sh | bash
```

---

## Structure du projet (pour référence)

```
ChillApp/
├── cli/
│   ├── chill          # CLI Linux/macOS
│   └── chill.ps1      # CLI Windows
├── scripts/
│   ├── install.sh     # Script install Linux/macOS (pour le site web)
│   ├── install.ps1    # Script install Windows (pour le site web)
│   └── package-release.sh  # Packaging des releases
└── dist/              # Généré par package-release.sh (gitignore)
```

## Ce qui est déjà fait (ne pas refaire)

- ✅ Purge historique git (docs/, CLAUDE.md, etc. supprimés de tous les commits)
- ✅ Scripts d'installation créés (install.sh + install.ps1)
- ✅ GitHub Release v1.0.0 créée avec build Linux
- ✅ CLI complet (chill status, info, start, stop, update, doctor, security...)
- ✅ Repo prêt à être rendu public (il manque juste le build Windows)
