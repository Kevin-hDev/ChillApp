#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
#  Chill — Script d'installation
#  Linux / macOS
#
#  Usage :
#    curl -fsSL https://raw.githubusercontent.com/Kevin-hDev/ChillApp/main/scripts/install.sh | bash
#
#  Variables optionnelles :
#    CHILL_DIR  — Dossier d'installation (défaut : ~/.local/share/chill)
#    BIN_DIR    — Dossier pour la commande chill (défaut : ~/.local/bin)
# ──────────────────────────────────────────────────────────
set -euo pipefail

GITHUB_REPO="Kevin-hDev/ChillApp"
CHILL_DIR="${CHILL_DIR:-$HOME/.local/share/chill}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DESKTOP_FILE="$HOME/.local/share/applications/chill.desktop"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
print_warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
print_err()  { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }
print_info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }

# ── Vérifications préalables ──────────────────────────────

check_deps() {
    local missing=()
    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        print_err "Outils requis manquants : ${missing[*]}"
        print_info "Installe-les avec ton gestionnaire de paquets, puis relance le script."
        exit 1
    fi
}

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)
            print_err "Système non supporté : $(uname -s)"
            print_info "Chill supporte Linux et macOS."
            exit 1
            ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            print_err "Architecture non supportée : $(uname -m)"
            exit 1
            ;;
    esac
}

# ── Téléchargement ────────────────────────────────────────

get_download_url() {
    local os="$1"
    local arch="$2"
    local asset_name="chill-${os}-${arch}.tar.gz"

    print_info "Recherche de la dernière version..." >&2

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local response
    response=$(curl -fsSL "$api_url") || {
        print_err "Impossible de contacter GitHub. Vérifie ta connexion internet."
        exit 1
    }

    local download_url
    download_url=$(printf '%s' "$response" \
        | grep "browser_download_url" \
        | grep "$asset_name" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\([^"]*\)".*/\1/')

    if [ -z "$download_url" ]; then
        print_err "Aucune release trouvée pour $asset_name"
        print_info "Vérifie les releases disponibles : https://github.com/${GITHUB_REPO}/releases" >&2
        exit 1
    fi

    # Validation de sécurité : URL doit être depuis GitHub
    if [[ "$download_url" != https://github.com/* ]] && [[ "$download_url" != https://objects.githubusercontent.com/* ]]; then
        print_err "URL de téléchargement suspecte : $download_url"
        exit 1
    fi

    echo "$download_url"
}

# ── Installation ──────────────────────────────────────────

install_chill() {
    local os="$1"
    local arch="$2"
    local download_url="$3"

    # Créer un dossier temporaire (variable globale pour le trap EXIT)
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    print_info "Téléchargement de Chill..."
    curl -fsSL --progress-bar "$download_url" -o "$TMP_DIR/chill.tar.gz"

    print_info "Vérification de l'archive..."
    if ! tar -tzf "$TMP_DIR/chill.tar.gz" &>/dev/null; then
        print_err "L'archive téléchargée est corrompue."
        exit 1
    fi

    print_info "Extraction..."
    tar -xzf "$TMP_DIR/chill.tar.gz" -C "$TMP_DIR"

    # Trouver le dossier extrait
    local extracted_dir
    extracted_dir=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -z "$extracted_dir" ]; then
        extracted_dir="$TMP_DIR"
    fi

    # Arrêter Chill s'il tourne
    if pgrep -x chill_app &>/dev/null; then
        print_info "Arrêt de Chill..."
        pkill -x chill_app || true
        sleep 1
    fi

    # Installer dans CHILL_DIR
    print_info "Installation dans $CHILL_DIR..."
    mkdir -p "$CHILL_DIR"
    cp -rf "$extracted_dir"/. "$CHILL_DIR/"

    # Permissions des exécutables
    chmod +x "$CHILL_DIR/chill_app" 2>/dev/null || true
    chmod +x "$CHILL_DIR/chill" 2>/dev/null || true
    chmod +x "$CHILL_DIR/chill-tailscale" 2>/dev/null || true
    chmod +x "$CHILL_DIR/chill-tailscale-macos" 2>/dev/null || true

    # Créer le dossier bin et le lien CLI
    mkdir -p "$BIN_DIR"
    ln -sf "$CHILL_DIR/chill" "$BIN_DIR/chill"

    # Lanceur .desktop (Linux uniquement)
    if [ "$os" = "linux" ]; then
        mkdir -p "$(dirname "$DESKTOP_FILE")"
        cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Chill
GenericName=Remote Access Configuration
Comment=Configure SSH, Wake-on-LAN and Tailscale easily
Exec=$CHILL_DIR/chill_app
Icon=$CHILL_DIR/data/flutter_assets/assets/images/icon.png
Categories=System;Network;
Keywords=ssh;tailscale;wol;remote;
StartupNotify=true
DESKTOP
        chmod 644 "$DESKTOP_FILE"
    fi
}

# ── Configuration du PATH ─────────────────────────────────

configure_path() {
    # Vérifier si BIN_DIR est déjà dans le PATH
    if echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
        return 0
    fi

    # Détecter le shell et le fichier de config à modifier
    local shell_config=""
    local shell_name
    shell_name=$(basename "${SHELL:-bash}")

    case "$shell_name" in
        bash) shell_config="$HOME/.bashrc" ;;
        zsh)  shell_config="$HOME/.zshrc" ;;
        fish)
            # Fish utilise une syntaxe différente
            local fish_config="$HOME/.config/fish/conf.d/chill.fish"
            mkdir -p "$(dirname "$fish_config")"
            echo "fish_add_path $BIN_DIR" > "$fish_config"
            print_ok "PATH configuré pour Fish"
            return 0
            ;;
        *)    shell_config="$HOME/.profile" ;;
    esac

    if [ -n "$shell_config" ]; then
        if ! grep -q "$BIN_DIR" "$shell_config" 2>/dev/null; then
            printf '\n# Chill CLI\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$shell_config"
            print_ok "PATH configuré dans $shell_config"
        fi
    fi
}

# ── Main ──────────────────────────────────────────────────

main() {
    printf "\n${BOLD}  Installation de Chill${NC}\n\n"

    check_deps

    local os arch download_url version
    os=$(detect_os)
    arch=$(detect_arch)

    download_url=$(get_download_url "$os" "$arch")
    version=$(printf '%s' "$download_url" | grep -oP 'v[\d.]+' | head -1 || echo "")

    print_info "OS : $os | Architecture : $arch${version:+ | Version : $version}"

    install_chill "$os" "$arch" "$download_url"

    configure_path

    printf "\n  ${GREEN}${BOLD}Chill installé avec succès !${NC}\n\n"

    # Vérifier si chill est accessible dans le PATH actuel
    if command -v chill &>/dev/null || [ -x "$BIN_DIR/chill" ]; then
        printf "  Commandes disponibles :\n\n"
        printf "    ${CYAN}chill status${NC}    — État de SSH, WoL, Tailscale\n"
        printf "    ${CYAN}chill info${NC}      — Ton IP, MAC, hostname\n"
        printf "    ${CYAN}chill start${NC}     — Ouvrir l'application\n"
        printf "    ${CYAN}chill doctor${NC}    — Diagnostic de l'installation\n"
        printf "    ${CYAN}chill help${NC}      — Toutes les commandes\n"
        printf "\n"
    fi

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
        printf "  ${YELLOW}!${NC} Ouvre un nouveau terminal (ou fais ${CYAN}source ~/.bashrc${NC}) pour utiliser ${BOLD}chill${NC}\n\n"
    fi

    printf "  ${CYAN}→${NC} Lance l'app : ${BOLD}chill start${NC}\n\n"
}

main "$@"
