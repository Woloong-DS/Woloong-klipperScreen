#!/bin/bash
# Woloong Theme Uninstaller for KlipperScreen
# Restores official default state using deploy.sh backups.
# Usage: ./R_deploy.sh [--path /path/to/KlipperScreen]

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
    echo -e "  (Theme may have already been removed.)"
fi

# ── Step 3: Restore config from deploy.sh backup (if available) ──
CONFIG_FILE=$(find_config_file "$TARGET_PATH")
if [ -n "$CONFIG_FILE" ]; then
    echo -e "${CYAN}Checking config file: ${CONFIG_FILE}${NC}"
    
    # Look for the oldest deploy.sh backup (most likely the original file)
    DEPLOY_BACKUP=$(ls -1 "${CONFIG_FILE}.backup."* 2>/dev/null | sort | head -n1)
    
    if [ -n "$DEPLOY_BACKUP" ]; then
        echo -e "  ${CYAN}Found deploy backup: ${DEPLOY_BACKUP}${NC}"
        cp "$DEPLOY_BACKUP" "$CONFIG_FILE"
        echo -e "${GREEN}Config restored from deploy backup.${NC}"
    else
        # No deploy backup found: just comment out the theme line if present
        if grep -qE "^theme\s*=\s*${THEME_NAME}\b" "$CONFIG_FILE"; then
            sed -i "s/^theme\s*=\s*${THEME_NAME}.*/# theme = ${THEME_NAME}  (uninstalled $(date +%Y-%m-%d))/" "$CONFIG_FILE"
            echo -e "${YELLOW}No deploy backup found. Theme line commented out.${NC}"
        elif grep -qE '^theme\s*=' "$CONFIG_FILE"; then
            echo -e "  ${YELLOW}Another theme is set. No change made.${NC}"
        else
            echo -e "  ${CYAN}No theme setting found. Nothing to modify.${NC}"
        fi
    fi
else
    echo -e "${YELLOW}No KlipperScreen.conf found. Manual config cleanup may be needed.${NC}"
fi

# ── Step 3.5: Restore original splash_screen.py from deploy.sh backup ──
TARGET_PANEL="${TARGET_PATH}/panels/splash_screen.py"
if [ -f "$TARGET_PANEL" ]; then
    # Look for the oldest deploy.sh backup (most likely the original file)
    PANEL_BACKUP=$(ls -1 "${TARGET_PANEL}.backup."* 2>/dev/null | sort | head -n1)
    
    if [ -n "$PANEL_BACKUP" ]; then
        echo -e "${CYAN}Found splash_screen backup: ${PANEL_BACKUP}${NC}"
        cp "$PANEL_BACKUP" "$TARGET_PANEL"
        echo -e "${GREEN}Original splash_screen.py restored from deploy backup.${NC}"
    else
        echo -e "${YELLOW}No deploy backup for splash_screen.py found. File left as-is.${NC}"
    fi
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
echo -e "    ${CYAN}./deploy.sh${NC}"
echo ""
