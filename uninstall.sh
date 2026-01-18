#!/bin/bash
#
# gamdl Chrome Extension - Uninstall Utility
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

HOST_NAME="com.gamdl.host"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    NATIVE_HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    NATIVE_HOST_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
else
    echo -e "${RED}Error: Unsupported operating system${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}gamdl Chrome Extension Uninstaller${NC}"
echo ""

# Remove native messaging host
MANIFEST_FILE="$NATIVE_HOST_DIR/$HOST_NAME.json"

if [[ -f "$MANIFEST_FILE" ]]; then
    echo -e "Found native messaging host manifest:"
    echo -e "  ${CYAN}$MANIFEST_FILE${NC}"
    echo ""
    read -p "Remove native messaging host? (Y/n): " remove_host

    if [[ ! "$remove_host" =~ ^[Nn]$ ]]; then
        rm "$MANIFEST_FILE"
        echo -e "${GREEN}✓${NC} Native messaging host removed"
    else
        echo -e "${YELLOW}⚠${NC} Skipped"
    fi
else
    echo -e "${YELLOW}⚠${NC} Native messaging host not found (already removed?)"
fi

echo ""

# Offer to remove config
CONFIG_FILE="$HOME/.gamdl/config.ini"

if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "Found gamdl config file:"
    echo -e "  ${CYAN}$CONFIG_FILE${NC}"
    echo ""
    read -p "Remove gamdl config? (y/N): " remove_config

    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        rm "$CONFIG_FILE"
        echo -e "${GREEN}✓${NC} Config removed"
    else
        echo -e "${YELLOW}⚠${NC} Config kept"
    fi
fi

echo ""
echo -e "${BOLD}Manual steps:${NC}"
echo ""
echo "1. Open ${CYAN}chrome://extensions${NC}"
echo "2. Find 'gamdl - Apple Music Downloader'"
echo "3. Click ${BOLD}Remove${NC}"
echo ""
echo -e "${GREEN}Uninstall complete!${NC}"
echo ""
