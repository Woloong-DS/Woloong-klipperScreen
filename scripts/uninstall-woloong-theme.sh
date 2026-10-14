#!/bin/bash
# Woloong Theme Uninstaller for KlipperScreen
# Removes the Woloong theme files and restores previous theme configuration.
# Usage: ./uninstall-woloong-theme.sh [--path /path/to/KlipperScreen]

set -e

THEME_NAME="woloong"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║             Woloong Theme Uninstaller                    ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Common installation paths to probe
probe_klipper_screen_path() {
    local paths=(
        "$HOME/KlipperScreen"
        "/home/pi/KlipperScreen"
        "/home/${USER}/KlipperScreen"
        "/opt/KlipperScreen"
        "/usr/share/KlipperScreen"
    )

    for p in "${paths[@]}"; do
        if [ -d "$p" ] && [ -f "$p/screen.py" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# Find config file location
find_config_file() {
    local ks_path="$1"
    local configs=(
        "$HOME/printer_data/config/KlipperScreen.conf"
        "$HOME/.config/KlipperScreen/KlipperScreen.conf"
        "${ks_path}/KlipperScreen.conf"
    )

    for c in "${configs[@]}"; do
        if [ -f "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

print_banner

# ── Step 1: Detect target path ──
TARGET_PATH=""
if [ -n "$1" ] && [ "$1" = "--path" ] && [ -n "$2" ]; then
    TARGET_PATH="$2"
    echo -e "${CYAN}Using user-specified path: ${TARGET_PATH}${NC}"
else
    echo -e "${CYAN}Detecting KlipperScreen installation...${NC}"
    TARGET_PATH=$(probe_klipper_screen_path)
    if [ -n "$TARGET_PATH" ]; then
        echo -e "${GREEN}Found KlipperScreen at: ${TARGET_PATH}${NC}"
    else
        echo -e "${YELLOW}Could not auto-detect KlipperScreen installation.${NC}"
        echo "Please specify the path manually:"
        read -r -p "KlipperScreen path (e.g., /home/pi/KlipperScreen): " TARGET_PATH
        if [ -z "$TARGET_PATH" ]; then
            echo -e "${RED}No path provided. Aborting.${NC}"
            exit 1
        fi
    fi
fi

TARGET_THEME_DIR="${TARGET_PATH}/styles/${THEME_NAME}"

# ── Step 2: Remove theme files ──
if [ -d "$TARGET_THEME_DIR" ]; then
    echo -e "${CYAN}Removing theme directory: ${TARGET_THEME_DIR}${NC}"
    rm -rf "$TARGET_THEME_DIR"
    echo -e "${GREEN}Theme files removed.${NC}"
else
    echo -e "${YELLOW}Theme directory not found: ${TARGET_THEME_DIR}${NC}"
    echo -e "  (Theme may have already been removed or installed elsewhere.)"
fi

# ── Step 3: Restore config ──
CONFIG_FILE=$(find_config_file "$TARGET_PATH")
if [ -n "$CONFIG_FILE" ]; then
    echo -e "${CYAN}Updating config file: ${CONFIG_FILE}${NC}"
    
    # Backup config first
    CONFIG_BACKUP="${CONFIG_FILE}.backup.uninstall.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    echo -e "  ${CYAN}Config backed up to: ${CONFIG_BACKUP}${NC}"
    
    # Remove or comment out theme line
    if grep -q "^theme\s*=\s*${THEME_NAME}" "$CONFIG_FILE"; then
        # Comment out the line instead of deleting, preserving user reference
        sed -i "s/^theme\s*=\s*${THEME_NAME}.*/# theme = ${THEME_NAME}  (uninstalled $(date +%Y-%m-%d))/" "$CONFIG_FILE"
        echo -e "${GREEN}Theme setting commented out in config.${NC}"
    elif grep -q "^theme\s*=" "$CONFIG_FILE"; then
        echo -e "${YELLOW}Another theme is currently set in config. No change made.${NC}"
    else
        echo -e "${CYAN}No theme setting found in config. Nothing to modify.${NC}"
    fi
else
    echo -e "${YELLOW}No KlipperScreen.conf found. Manual config cleanup may be needed.${NC}"
fi

# ── Step 4: Optional restart ──
echo ""
echo -e "${CYAN}Would you like to restart KlipperScreen to complete uninstall? (Y/n)${NC}"
read -r restart
if [[ ! "$restart" =~ ^[Nn]$ ]]; then
    echo -e "${CYAN}Restarting KlipperScreen...${NC}"
    if systemctl restart KlipperScreen 2>/dev/null; then
        echo -e "${GREEN}KlipperScreen restarted successfully.${NC}"
    elif sudo systemctl restart KlipperScreen 2>/dev/null; then
        echo -e "${GREEN}KlipperScreen restarted successfully (via sudo).${NC}"
    else
        echo -e "${YELLOW}Could not restart automatically. Please restart manually:${NC}"
        echo -e "  ${CYAN}sudo systemctl restart KlipperScreen${NC}"
    fi
else
    echo -e "${YELLOW}Skipped restart. Please restart manually when ready.${NC}"
fi

# ── Done ──
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Woloong Theme uninstallation complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Theme removed from:${NC} ${TARGET_THEME_DIR}"
echo -e "  ${CYAN}Config updated:${NC}   ${CONFIG_FILE:-Not found}"
echo ""
echo -e "  ${YELLOW}To reinstall, run:${NC}"
echo -e "    ${CYAN}./scripts/install-woloong-theme.sh${NC}"
echo ""
