#!/bin/bash
#
# Dotfiles Installation Script
# Self-contained deployment for fresh Hyprland installations on CachyOS/Arch
#
# Usage: ./install.sh [options]
#   --dry-run    Show what would be done without making changes
#   --no-backup  Skip creating backups of existing configs
#   --help       Show this help message
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
NO_BACKUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --no-backup) NO_BACKUP=true; shift ;;
        --help)
            head -n 10 "$0" | tail -n 6
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Helper functions
info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

execute() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        warning "$1 not found - some features may not work"
        return 1
    fi
    return 0
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Hyprland Dotfiles Installation                          ║
║   CachyOS/Arch Edition                                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running on Arch-based system
if [ ! -f /etc/arch-release ]; then
    warning "This script is designed for Arch-based systems"
    read -p "Continue anyway? (y/N) " -n 1 -r || true
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# ------------------------------------------------------------------
# Packages
# ------------------------------------------------------------------
# Everything the configs, keybinds, and scripts reference.
# Availability is checked at runtime: packages found in the configured
# pacman repos are installed with pacman, the rest go to the AUR helper.
PACKAGES=(
    # Hyprland ecosystem
    "hyprland" "hyprlock" "hypridle" "hyprpolkitagent"
    "hyprshot" "hyprpicker" "hyprsunset" "swappy"
    # Session manager; XDG autostart (the panel's Startup page) runs through it
    "uwsm"
    # Portals named in xdg-desktop-portal/hyprland-portals.conf
    "xdg-desktop-portal-hyprland" "xdg-desktop-portal-gtk"
    # Bar, notifications, OSD, wallpaper
    "waybar" "swaync" "awww" "waypaper" "quickshell"
    # Launchers and menus
    "rofi" "rofi-emoji"
    # Terminals, shell, editors
    "ghostty" "fish" "starship" "fzf" "fd" "neovim" "zed"
    # Notes, on Super+T
    "obsidian"
    # fzf.fish previews (bat/config is themed); LazyVim's grep, git UI and parsers
    "bat" "eza" "ripgrep" "lazygit" "tree-sitter-cli"
    # File managers and system tools
    "yazi" "btop" "resources" "fastfetch" "cava"
    # Terminal toys the fish aliases run in the accent (scripts/theming/accent-run.sh)
    "cmatrix" "tty-clock"
    # checkupdates, for the waybar updates module
    "pacman-contrib"
    # Opens Terminal=true desktop entries in options/terminal (scripts/settings/terminal.sh)
    "xdg-terminal-exec"
    # Clipboard, screenshots, screen recording, media
    "cliphist" "wl-clipboard" "gpu-screen-recorder" "slurp" "playerctl"
    # Theming
    "matugen" "qt5ct" "qt6ct" "nwg-look"
    # Qt style and icon theme that defaults/ name
    "kvantum" "kvantum-qt5" "papirus-icon-theme"
    # Applets and controls
    "pavucontrol" "blueman" "nm-connection-editor"
    "gnome-calculator"
    # wpctl (volume keys, sound popover) and pactl (scripts/sound/sound.sh)
    "wireplumber" "pipewire-pulse"
    # nmcli and powerprofilesctl, read by the settings panel
    "networkmanager" "power-profiles-daemon"
    # Secret Service: the calendar's passwords live in the keyring
    "gnome-keyring"
    # Calendar sync (scripts/calendar, docs/calendar.md)
    "khal" "vdirsyncer"
    # Headset battery, for scripts/devices/devices.sh
    "headsetcontrol"
    # Script dependencies
    "jq" "ffmpeg" "inotify-tools" "zoxide" "git-delta" "aichat" "shellcheck"
    # Palette tests render a real image (scripts/theming/test)
    "imagemagick"
    # SpotX repacks Spotify's xpui.spa (scripts/spotify/launch.sh)
    "zip" "unzip"
    # Native Waybar workspace module (scripts/waybar/build-workspaces.sh)
    "gcc" "make" "pkgconf" "gtk3" "json-glib"
    # Isolated deployment/hook fixtures, panel persistence tests and the settings overlay (scripts/state)
    "python" "nodejs" "gjs"
    # Fonts (configs default to FiraCode Nerd Font)
    "ttf-firacode-nerd" "ttf-cascadia-mono-nerd" "ttf-nerd-fonts-symbols"
    "noto-fonts" "noto-fonts-emoji"
)

AUR_PACKAGES=(
    "strata-bin"             # GTK4 file manager
    "zen-browser-bin"
    "vesktop"
    "waybar-weather"
    "eww"                    # desktop clock widget (scripts/desktop-clock)
    "bibata-cursor-theme"    # default cursor (defaults/options/cursortheme)
    "kripton-theme-git"      # default GTK theme (defaults/gtk-*/settings.ini)
)

info "Checking system dependencies..."
MISSING_PACMAN=()
MISSING_AUR=("${AUR_PACKAGES[@]}")
for pkg in "${PACKAGES[@]}"; do
    if pacman -Qq "$pkg" &> /dev/null; then
        continue
    fi
    if pacman -Si "$pkg" &> /dev/null; then
        MISSING_PACMAN+=("$pkg")
    else
        # Not in any configured repo - try the AUR instead
        MISSING_AUR+=("$pkg")
    fi
done

if [ ${#MISSING_PACMAN[@]} -gt 0 ]; then
    warning "Missing packages: ${MISSING_PACMAN[*]}"
    read -p "Install missing packages? (y/N) " -n 1 -r || true
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        execute sudo pacman -S --needed "${MISSING_PACMAN[@]}"
        success "Packages installed"
    else
        warning "Skipping package installation - some features may not work"
    fi
fi

info "Checking AUR packages..."
STILL_MISSING_AUR=()
for pkg in "${MISSING_AUR[@]}"; do
    # Accept either the package itself or its non -bin/-git variant
    if ! pacman -Qq "$pkg" &> /dev/null \
        && ! pacman -Qq "${pkg%-bin}" &> /dev/null \
        && ! pacman -Qq "${pkg}-git" &> /dev/null; then
        STILL_MISSING_AUR+=("$pkg")
    fi
done

if [ ${#STILL_MISSING_AUR[@]} -gt 0 ]; then
    warning "Missing AUR packages: ${STILL_MISSING_AUR[*]}"
    if command -v paru &> /dev/null || command -v yay &> /dev/null; then
        read -p "Install missing AUR packages? (y/N) " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            AUR_HELPER=$(command -v paru || command -v yay)
            execute "$AUR_HELPER" -S --needed "${STILL_MISSING_AUR[@]}"
            success "AUR packages installed"
        fi
    else
        warning "No AUR helper found (paru/yay). Install manually: ${STILL_MISSING_AUR[*]}"
    fi
fi

# ------------------------------------------------------------------
# Back up and deploy the same tracked-file plan
# ------------------------------------------------------------------
if [ "$DOTFILES_DIR" != "$CONFIG_DIR" ]; then
    info "Deploying tracked dotfiles to $CONFIG_DIR..."
    # shellcheck source=scripts/lib/deploy.sh
    source "$DOTFILES_DIR/scripts/lib/deploy.sh"
    deploy_dotfiles "$DOTFILES_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$DRY_RUN" "$NO_BACKUP"
    success "Tracked dotfiles deployed"
    [ "$NO_BACKUP" = true ] || info "Backup saved to: $BACKUP_DIR"
else
    info "Repo already lives at $CONFIG_DIR - no deployment needed"
fi

# Render this machine's settings: tracked defaults/ plus per-machine overrides
# (scripts/state/overlay.sh). A live file that predates the overlay is backed up
# and replaced, as the deploy step replaces a config, so a fresh install starts
# from the repo's defaults.
overlay_backup=""
[ "$NO_BACKUP" = true ] || overlay_backup="$BACKUP_DIR/overlay"
if ! execute bash "$CONFIG_DIR/scripts/state/overlay.sh" sync --replace "$overlay_backup"; then
    warning "Some settings could not be rendered; run scripts/state/overlay.sh sync to retry"
fi

# ------------------------------------------------------------------
# Directories and wallpapers
# ------------------------------------------------------------------
info "Setting up directory structure..."
execute mkdir -p "$HOME/.cache/wal"
execute mkdir -p "$HOME/.cache/awww"
execute mkdir -p "$HOME/Pictures/Wallpapers"
execute mkdir -p "$HOME/Pictures/Screenshots"
success "Directories created"

info "Copying wallpapers..."
if [ -d "$CONFIG_DIR/wallpapers" ]; then
    execute cp -n "$CONFIG_DIR/wallpapers/"* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
    success "Wallpapers copied"
fi

# ------------------------------------------------------------------
# Palette initialization
# ------------------------------------------------------------------
info "Initializing color palette..."
FIRST_WALLPAPER="$CONFIG_DIR/wallpapers/wall1.jpg"
if [ ! -f "$FIRST_WALLPAPER" ]; then
    FIRST_WALLPAPER=$(find "$HOME/Pictures/Wallpapers" -type f \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | head -n 1)
fi
if [ -n "$FIRST_WALLPAPER" ] && check_dependency "matugen" \
        && execute "$CONFIG_DIR/scripts/theming/generate-palette.sh" "$FIRST_WALLPAPER"; then
    success "Palette initialized"
else
    warning "Could not generate a palette - change the wallpaper (Super+Ctrl+W) to retry"
fi

# Current-wallpaper state + generated configs (cache-backed, symlinked from the repo)
if [ -n "$FIRST_WALLPAPER" ]; then
    execute ln -sfn "$FIRST_WALLPAPER" "$HOME/.cache/current_wallpaper"
    if [ "$DRY_RUN" = false ]; then
        echo "* { wallpaper: url(\"$FIRST_WALLPAPER\", width); }" > "$HOME/.cache/wal/rofi-wallpaper.rasi"
    else
        echo "[DRY RUN] write $HOME/.cache/wal/rofi-wallpaper.rasi"
    fi
    success "Wallpaper state initialized"
fi

# Render every themed component's colors (cache-backed, reached from tracked
# configs by symlink or include). The driver globs for the per-component
# scripts, and each one produces its output even before palette generation, so
# no component needs a fallback here.
if ! execute "$CONFIG_DIR/scripts/theming/apply-wal.sh"; then
    warning "Some theme components failed; run scripts/theming/apply-wal.sh to retry"
fi

# "Show in folder" everywhere goes through D-Bus; several file managers claim
# that service, so point it at the one in options/filemanager.
execute bash "$CONFIG_DIR/scripts/settings/file-manager.sh"
# Register Strata as the portal file chooser, with GTK as the fallback.
execute bash "$CONFIG_DIR/scripts/settings/file-chooser.sh"

# Desktop entries with Terminal=true (nvim, yazi, btop) open through
# xdg-terminal-exec; point it at options/terminal.
execute bash "$CONFIG_DIR/scripts/settings/terminal.sh"

# Spotify (if spotify-launcher is installed) starts through a wrapper that
# keeps SpotX applied across client updates; this points its desktop entry there.
if ! execute bash "$CONFIG_DIR/scripts/spotify/setup.sh"; then
    warning "Spotify desktop entry not set up; run scripts/spotify/setup.sh to retry"
fi

# With Spicetify set up, select the palette-coloured theme and its live-recolour
# extension (Spicetify's own config is per-machine and untracked).
if ! execute bash "$CONFIG_DIR/scripts/spotify/spicetify-theme.sh"; then
    warning "Spicetify theme not selected; run scripts/spotify/spicetify-theme.sh to retry"
fi

if ! execute bash "$CONFIG_DIR/scripts/waybar/clock-format.sh" --no-reload; then
    warning "Could not render the Waybar clock format"
fi

if ! execute bash "$CONFIG_DIR/scripts/waybar/bar-modes.sh" --no-reload; then
    warning "Could not render the Waybar module modes"
fi

if ! execute bash "$CONFIG_DIR/scripts/waybar/build-workspaces.sh"; then
    warning "The Waybar workspace module did not build; run scripts/waybar/build-workspaces.sh to retry"
fi

# Seed waypaper config
if [ ! -f "$HOME/.cache/waypaper-config.ini" ]; then
    execute cp "$CONFIG_DIR/waypaper/config.ini.template" "$HOME/.cache/waypaper-config.ini"
fi

# ------------------------------------------------------------------
# Git hooks
# ------------------------------------------------------------------
# Tracked hooks live in scripts/hooks and are activated by pointing git at
# them, so they update with a pull instead of rotting in .git/hooks.
if [ -d "$CONFIG_DIR/.git" ]; then
    info "Activating tracked git hooks..."
    execute git -C "$CONFIG_DIR" config core.hooksPath scripts/hooks
    success "Pre-commit gate active (shellcheck + test suites)"
fi

# ------------------------------------------------------------------
# SSH agent
# ------------------------------------------------------------------
# Passphrase once per login: OpenSSH's socket-activated agent plus the tracked
# ssh/config, included from ~/.ssh/config. Not a prompt: ~/.ssh/config is
# backed up before it changes, like every config the deploy step replaces.
# This MUST stay after deploy_dotfiles: that refuses a $BACKUP_DIR which
# already exists, and this step creates $BACKUP_DIR/.ssh.
info "Setting up the SSH agent..."
ssh_setup_args=()
if [ "$DRY_RUN" = true ]; then
    ssh_setup_args+=(--dry-run)
fi
if [ "$NO_BACKUP" = true ]; then
    ssh_setup_args+=(--no-backup)
else
    ssh_setup_args+=(--backup-dir "$BACKUP_DIR")
fi
# A dry run previews from the clone, since nothing has been deployed yet.
ssh_setup_root="$CONFIG_DIR"
if [ "$DRY_RUN" = true ]; then
    ssh_setup_root="$DOTFILES_DIR"
fi
bash "$ssh_setup_root/scripts/ssh/setup.sh" "${ssh_setup_args[@]}" \
    || warning "SSH agent setup reported a problem (see above)"

# ------------------------------------------------------------------
# Final wiring
# ------------------------------------------------------------------
# Script modes need no fixing here: git tracks the executable bit, and the
# deployment copies preserve it.

# AI agent harness (Claude Code / Codex / Herdr) lives in its own repository.
# It installs the repo owner's personal agent instructions, skills and
# plugins, so it is opt-in (default No) and only offered when one of those
# tools is installed and the harness has been cloned.
if command -v claude &> /dev/null || command -v codex &> /dev/null; then
    HARNESS_DIR="$HOME/Developer/agent-harness"
    if [ ! -x "$HARNESS_DIR/setup.sh" ]; then
        info "AI agent harness (optional): git clone https://github.com/pwnjack/agent-harness.git ~/Developer/agent-harness, then run its setup.sh"
    elif [ "$DRY_RUN" = true ]; then
        info "AI agent harness (opt-in) would do:"
        bash "$HARNESS_DIR/setup.sh" --dry-run || warning "Agent harness dry run reported a problem (see above)"
    else
        read -p "Install the AI agent harness (Claude Code/Codex skills, instructions, plugins)? (y/N) " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bash "$HARNESS_DIR/setup.sh" || warning "Agent harness setup reported a problem (see above)"
        fi
    fi
fi

# iCloud calendar: never prompts. Enables the sync timer when an account is
# already stored; otherwise points at Settings > Calendar.
if ! execute bash "$CONFIG_DIR/scripts/calendar/setup.sh"; then
    warning "Calendar sync timer not enabled; run scripts/calendar/setup.sh to retry"
fi

# API keys template
if [ ! -f "$CONFIG_DIR/.env" ] && [ -f "$CONFIG_DIR/.env.example" ]; then
    execute cp "$CONFIG_DIR/.env.example" "$CONFIG_DIR/.env"
    success "Created $CONFIG_DIR/.env from template (add your API keys there)"
fi

# Set fish as default shell
if check_dependency "fish"; then
    if [ "$SHELL" != "$(which fish)" ]; then
        read -p "Set fish as default shell? (y/N) " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            execute chsh -s "$(which fish)"
            success "Fish set as default shell (logout to apply)"
        fi
    else
        success "Fish is already default shell"
    fi
fi

# Print summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   Installation Complete!                                  ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Next steps:"
echo "  1. Log out and log back in (or reboot)"
echo "  2. Select Hyprland from your login manager"
echo "  3. Press SUPER+ENTER to open terminal (ghostty)"
echo "  4. Press SUPER+CTRL+W to pick a wallpaper (colors follow automatically)"
echo ""
info "Key bindings:"
echo "  SUPER+ENTER      - Terminal"
echo "  SUPER+Q          - Close window"
echo "  SUPER+SPACE      - Application launcher"
echo "  SUPER+L          - Lock screen"
echo "  SUPER+SHIFT+L    - Power menu"
echo "  SUPER+H          - Keybinds cheatsheet"
echo ""
if [ "$NO_BACKUP" = false ] && { [ "$DOTFILES_DIR" != "$CONFIG_DIR" ] || [ -d "$BACKUP_DIR" ]; }; then
    info "Backup location: $BACKUP_DIR"
fi
echo ""
success "Enjoy your new Hyprland setup!"
