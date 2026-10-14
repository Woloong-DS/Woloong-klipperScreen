#!/bin/bash
# Woloong Theme Installer for KlipperScreen
# Automatically detects KlipperScreen installation, deploys theme, and configures.
# Usage: ./install.sh [--path /path/to/KlipperScreen]

set -e

THEME_NAME="woloong"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_THEME_DIR="${SCRIPT_DIR}/../styles/${THEME_NAME}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Brand banner
print_banner() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              Woloong Theme Installer                      ║${NC}"
    echo -e "${RED}║     DIY Precision + Industrial Tech Aesthetic           ║${NC}"
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

# Check if source theme exists
if [ ! -d "$SOURCE_THEME_DIR" ]; then
    echo -e "${RED}Error: Source theme directory not found at:${NC}"
    echo "  $SOURCE_THEME_DIR"
    echo -e "${YELLOW}Please run this script from the KlipperScreen-Woloong repository root.${NC}"
    exit 1
fi

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

# Validate target
if [ ! -d "$TARGET_PATH" ]; then
    echo -e "${RED}Error: Directory does not exist: ${TARGET_PATH}${NC}"
    exit 1
fi
if [ ! -f "$TARGET_PATH/screen.py" ]; then
    echo -e "${YELLOW}Warning: screen.py not found in ${TARGET_PATH}. Proceed anyway? (y/N)${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

TARGET_STYLES="${TARGET_PATH}/styles"
if [ ! -d "$TARGET_STYLES" ]; then
    echo -e "${YELLOW}Creating styles directory: ${TARGET_STYLES}${NC}"
    mkdir -p "$TARGET_STYLES"
fi

# ── Step 2: Backup existing theme if present ──
TARGET_THEME_DIR="${TARGET_STYLES}/${THEME_NAME}"
if [ -d "$TARGET_THEME_DIR" ]; then
    BACKUP_DIR="${TARGET_THEME_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Existing theme found. Creating backup: ${BACKUP_DIR}${NC}"
    cp -r "$TARGET_THEME_DIR" "$BACKUP_DIR"
fi

# ── Step 3: Deploy theme files ──
echo -e "${CYAN}Deploying theme files...${NC}"
rm -rf "$TARGET_THEME_DIR"
cp -r "$SOURCE_THEME_DIR" "$TARGET_THEME_DIR"
echo -e "${GREEN}Theme deployed to: ${TARGET_THEME_DIR}${NC}"

# Verify file count
FILE_COUNT=$(find "$TARGET_THEME_DIR" -type f | wc -l)
echo -e "  ${CYAN}Files deployed: ${FILE_COUNT}${NC}"

# ── Step 4: Configure KlipperScreen.conf ──
CONFIG_FILE=$(find_config_file "$TARGET_PATH")
if [ -n "$CONFIG_FILE" ]; then
    echo -e "${CYAN}Config file found: ${CONFIG_FILE}${NC}"
    
    # Backup config
    CONFIG_BACKUP="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    echo -e "  ${CYAN}Config backed up to: ${CONFIG_BACKUP}${NC}"
    
    # Check if [main] section exists
    if grep -q '^\[main\]' "$CONFIG_FILE"; then
        # Check if theme already set
        if grep -q '^theme\s*=' "$CONFIG_FILE"; then
            # Replace existing theme line
            sed -i "s/^theme\s*=.*/theme = ${THEME_NAME}/" "$CONFIG_FILE"
            echo -e "${GREEN}Updated theme setting in config.${NC}"
        else
            # Insert theme under [main]
            sed -i "/^\[main\]/a theme = ${THEME_NAME}" "$CONFIG_FILE"
            echo -e "${GREEN}Added theme setting to [main] section.${NC}"
        fi
    else
        # Create [main] section at top
        echo -e "${YELLOW}No [main] section found. Appending to top of config.${NC}"
        {
            echo "[main]"
            echo "theme = ${THEME_NAME}"
            echo ""
        } | cat - "$CONFIG_FILE" > temp_config && mv temp_config "$CONFIG_FILE"
    fi
else
    echo -e "${YELLOW}No existing KlipperScreen.conf found.${NC}"
    echo -e "  ${CYAN}Please create a config file with the following content:${NC}"
    echo ""
    echo -e "  ${YELLOW}[main]${NC}"
    echo -e "  ${YELLOW}theme = ${THEME_NAME}${NC}"
    echo ""
    echo -e "  ${CYAN}Common locations:${NC}"
    echo -e "    - ~/printer_data/config/KlipperScreen.conf"
    echo -e "    - ~/.config/KlipperScreen/KlipperScreen.conf"
    echo -e "    - ${TARGET_PATH}/KlipperScreen.conf"
fi

# ── Step 5: Restart service (optional) ──
echo ""
echo -e "${CYAN}Would you like to restart KlipperScreen to apply the theme? (Y/n)${NC}"
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
echo -e "${GREEN}  Woloong Theme installation complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Theme location:${NC}   ${TARGET_THEME_DIR}"
echo -e "  ${CYAN}Config file:${NC}      ${CONFIG_FILE:-Not found (manual setup needed)}"
echo -e "  ${CYAN}Theme name:${NC}       ${THEME_NAME}"
echo ""
echo -e "  ${YELLOW}To uninstall later, run:${NC}"
echo -e "    ${CYAN}./scripts/uninstall-woloong-theme.sh${NC}"
echo ""
