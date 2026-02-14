#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
#  Chill — Script de packaging des releases GitHub
#
#  Usage :
#    ./scripts/package-release.sh [version]
#
#  Exemples :
#    ./scripts/package-release.sh 1.0.0
#    ./scripts/package-release.sh          # utilise le fichier VERSION
#
#  Produit :
#    dist/chill-linux-x64.tar.gz
#    dist/chill-windows-x64.zip     (si build Windows disponible)
#    dist/chill-macos-x64.tar.gz    (si build macOS disponible)
#    dist/chill-macos-arm64.tar.gz  (si build macOS ARM disponible)
# ──────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
CLI_DIR="$PROJECT_DIR/cli"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
print_step() { printf "  ${CYAN}→${NC} %s\n" "$1"; }
print_err()  { printf "  ${RED}✗${NC} %s\n" "$1"; }

# ── Version ──────────────────────────────────────────────

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    if [ -f "$PROJECT_DIR/VERSION" ]; then
        VERSION=$(cat "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
    else
        print_err "Pas de version spécifiée et pas de fichier VERSION"
        printf "  Usage : %s <version>\n" "$0"
        exit 1
    fi
fi

printf "\n${BOLD}  Packaging Chill v${VERSION}${NC}\n\n"

# Créer le dossier dist
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ── Build Linux ──────────────────────────────────────────

package_linux() {
    print_step "Build Flutter Linux..."
    cd "$PROJECT_DIR"
    flutter build linux --release

    local bundle_dir="$PROJECT_DIR/build/linux/x64/release/bundle"
    if [ ! -d "$bundle_dir" ]; then
        print_err "Bundle Linux introuvable dans $bundle_dir"
        return 1
    fi

    local pkg_name="chill-linux-x64"
    local pkg_dir="$DIST_DIR/$pkg_name"
    mkdir -p "$pkg_dir"

    # Copier le bundle Flutter
    cp -r "$bundle_dir"/* "$pkg_dir/"

    # Copier le daemon Tailscale (s'il existe)
    local daemon_path="$PROJECT_DIR/assets/bin/chill-tailscale"
    if [ -f "$daemon_path" ]; then
        cp "$daemon_path" "$pkg_dir/"
        chmod +x "$pkg_dir/chill-tailscale"
    fi

    # Copier le CLI wrapper
    cp "$CLI_DIR/chill" "$pkg_dir/"
    chmod +x "$pkg_dir/chill"

    # Fichier VERSION
    echo "$VERSION" > "$pkg_dir/VERSION"

    # Archiver
    cd "$DIST_DIR"
    tar -czf "${pkg_name}.tar.gz" "$pkg_name"
    rm -rf "$pkg_dir"

    local size
    size=$(du -sh "$DIST_DIR/${pkg_name}.tar.gz" | cut -f1)
    print_ok "chill-linux-x64.tar.gz ($size)"
}

# ── Build Windows ────────────────────────────────────────

package_windows() {
    # Vérifier si on peut build Windows (cross-compilation pas supportée nativement)
    if [ "$(uname -s)" != "MINGW"* ] && [ "$(uname -s)" != "MSYS"* ]; then
        # On peut quand même packager si le build existe déjà
        local bundle_dir="$PROJECT_DIR/build/windows/x64/runner/Release"
        if [ ! -d "$bundle_dir" ]; then
            print_step "Build Windows non disponible (nécessite Windows)"
            return 0
        fi
    else
        print_step "Build Flutter Windows..."
        cd "$PROJECT_DIR"
        flutter build windows --release
        local bundle_dir="$PROJECT_DIR/build/windows/x64/runner/Release"
    fi

    local pkg_name="chill-windows-x64"
    local pkg_dir="$DIST_DIR/$pkg_name"
    mkdir -p "$pkg_dir"

    # Copier le bundle Flutter
    cp -r "$bundle_dir"/* "$pkg_dir/"

    # Copier le daemon Tailscale
    local daemon_path="$PROJECT_DIR/assets/bin/chill-tailscale.exe"
    if [ -f "$daemon_path" ]; then
        cp "$daemon_path" "$pkg_dir/"
    fi

    # Copier le CLI wrapper PowerShell
    cp "$CLI_DIR/chill.ps1" "$pkg_dir/"

    # Créer un wrapper .cmd pour que "chill" fonctionne dans cmd.exe
    cat > "$pkg_dir/chill.cmd" <<'CMD'
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0chill.ps1" %*
CMD

    # Fichier VERSION
    echo "$VERSION" > "$pkg_dir/VERSION"

    # Archiver en zip
    cd "$DIST_DIR"
    if command -v zip &>/dev/null; then
        zip -rq "${pkg_name}.zip" "$pkg_name"
    else
        # Fallback : tar.gz
        tar -czf "${pkg_name}.tar.gz" "$pkg_name"
        print_step "(zip non disponible, archive en .tar.gz)"
    fi
    rm -rf "$pkg_dir"

    local archive="${pkg_name}.zip"
    [ ! -f "$DIST_DIR/$archive" ] && archive="${pkg_name}.tar.gz"
    local size
    size=$(du -sh "$DIST_DIR/$archive" | cut -f1)
    print_ok "$archive ($size)"
}

# ── Build macOS ──────────────────────────────────────────

package_macos() {
    local arch="${1:-x64}"

    local bundle_dir="$PROJECT_DIR/build/macos/Build/Products/Release"
    if [ "$(uname -s)" = "Darwin" ]; then
        print_step "Build Flutter macOS..."
        cd "$PROJECT_DIR"
        flutter build macos --release
    else
        if [ ! -d "$bundle_dir" ]; then
            print_step "Build macOS non disponible (nécessite macOS)"
            return 0
        fi
    fi

    local pkg_name="chill-macos-${arch}"
    local pkg_dir="$DIST_DIR/$pkg_name"
    mkdir -p "$pkg_dir"

    # Copier le bundle Flutter (.app)
    cp -r "$bundle_dir"/*.app "$pkg_dir/" 2>/dev/null || true

    # Copier le daemon Tailscale macOS
    local daemon_path="$PROJECT_DIR/assets/bin/chill-tailscale-macos"
    if [ -f "$daemon_path" ]; then
        cp "$daemon_path" "$pkg_dir/"
        chmod +x "$pkg_dir/chill-tailscale-macos"
    fi

    # Copier le CLI wrapper
    cp "$CLI_DIR/chill" "$pkg_dir/"
    chmod +x "$pkg_dir/chill"

    # Fichier VERSION
    echo "$VERSION" > "$pkg_dir/VERSION"

    # Archiver
    cd "$DIST_DIR"
    tar -czf "${pkg_name}.tar.gz" "$pkg_name"
    rm -rf "$pkg_dir"

    local size
    size=$(du -sh "$DIST_DIR/${pkg_name}.tar.gz" | cut -f1)
    print_ok "chill-macos-${arch}.tar.gz ($size)"
}

# ── Main ─────────────────────────────────────────────────

package_linux
package_windows
package_macos "x64"
# package_macos "arm64"  # Décommenter quand un build ARM sera disponible

printf "\n${BOLD}  Packaging terminé !${NC}\n"
printf "  Fichiers dans : ${CYAN}%s${NC}\n\n" "$DIST_DIR"

# Lister les archives
ls -lh "$DIST_DIR"/*.{tar.gz,zip} 2>/dev/null | while read -r line; do
    printf "  %s\n" "$line"
done

printf "\n  ${BOLD}Prochaine étape :${NC} Upload les archives sur GitHub Releases\n"
printf "  ${CYAN}gh release create v%s %s/*${NC}\n\n" "$VERSION" "$DIST_DIR"
