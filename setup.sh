#!/bin/bash
#
# gamdl Chrome Extension - Setup Utility
# This script guides you through the complete installation process.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_HOST_DIR="$SCRIPT_DIR/native-host"
HOST_NAME="com.gamdl.host"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    NATIVE_HOST_TARGET="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    NATIVE_HOST_TARGET="$HOME/.config/google-chrome/NativeMessagingHosts"
else
    echo -e "${RED}Error: Unsupported operating system: $OSTYPE${NC}"
    exit 1
fi

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}gamdl Chrome Extension Setup${NC}                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Download Apple Music tracks directly from your browser       ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

check_dependencies() {
    print_step "Checking dependencies..."

    local missing=()

    # Check Python 3
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        print_success "Python 3 found: $python_version"
    else
        print_error "Python 3 not found"
        missing+=("python3")
    fi

    # Check for gamdl
    if command -v gamdl &> /dev/null; then
        local gamdl_path=$(command -v gamdl)
        print_success "gamdl found globally: $gamdl_path"
    elif python3 -c "import gamdl" 2>/dev/null; then
        print_success "gamdl module found"
    else
        print_warning "gamdl not found (install with: pipx install gamdl)"
        missing+=("gamdl")
    fi

    # Check ffmpeg
    if command -v ffmpeg &> /dev/null; then
        print_success "ffmpeg found"
    else
        print_warning "ffmpeg not found (required for audio processing)"
        if [[ "$OS" == "macos" ]]; then
            print_info "Install with: brew install ffmpeg"
        else
            print_info "Install with: sudo apt install ffmpeg"
        fi
    fi

    # Check for cookies file
    local cookies_path="$HOME/.gamdl/cookies.txt"
    if [[ -f "$cookies_path" ]]; then
        print_success "Cookies file found at $cookies_path"
    else
        print_warning "No cookies file found"
        print_info "You'll need to export cookies from Apple Music"
        print_info "Use a browser extension like 'Get cookies.txt LOCALLY'"
    fi

    echo ""

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Some dependencies are missing. The extension may not work correctly.${NC}"
        read -p "Continue anyway? (y/N): " continue_setup
        if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

setup_config() {
    print_step "Configuring gamdl..."

    local config_dir="$HOME/.gamdl"
    local config_file="$config_dir/config.ini"

    mkdir -p "$config_dir"

    if [[ -f "$config_file" ]]; then
        print_success "Config file exists: $config_file"
        read -p "  Would you like to reconfigure? (y/N): " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    echo ""
    echo "  Where should downloaded music be saved?"
    echo "  (Press Enter for default: ~/Music/Apple Music)"
    read -p "  Output path: " output_path

    if [[ -z "$output_path" ]]; then
        output_path="$HOME/Music/Apple Music"
    fi

    # Expand ~ if used
    output_path="${output_path/#\~/$HOME}"

    # Create directory if it doesn't exist
    mkdir -p "$output_path" 2>/dev/null || true

    if [[ ! -d "$output_path" ]]; then
        print_warning "Could not create directory: $output_path"
        print_info "Make sure the path is valid and you have write permissions"
    else
        print_success "Output directory: $output_path"
    fi

    # Check for existing cookies path
    local cookies_path="./cookies.txt"
    if [[ -f "$config_file" ]]; then
        existing_cookies=$(grep -E "^cookies_path" "$config_file" 2>/dev/null | cut -d'=' -f2 | xargs)
        if [[ -n "$existing_cookies" ]]; then
            cookies_path="$existing_cookies"
        fi
    fi

    # Write config
    cat > "$config_file" << EOF
[gamdl]
output_path = $output_path
cookies_path = $cookies_path
EOF

    print_success "Config saved to $config_file"
    echo ""
}

install_extension() {
    print_step "Installing Chrome extension..."

    echo ""
    echo "  To install the extension in Chrome:"
    echo ""
    echo "  1. Open Chrome and go to ${CYAN}chrome://extensions${NC}"
    echo "  2. Enable ${BOLD}Developer mode${NC} (toggle in top right)"
    echo "  3. Click ${BOLD}Load unpacked${NC}"
    echo "  4. Select this folder: ${CYAN}$SCRIPT_DIR${NC}"
    echo ""

    if [[ "$OS" == "macos" ]]; then
        read -p "  Open Chrome extensions page now? (Y/n): " open_chrome
        if [[ ! "$open_chrome" =~ ^[Nn]$ ]]; then
            open "chrome://extensions" 2>/dev/null || true
        fi
    fi

    echo ""
    echo "  After loading the extension, copy the ${BOLD}32-character ID${NC}"
    echo "  shown under the extension name."
    echo ""
    read -p "  Enter the extension ID: " extension_id

    # Validate extension ID
    if [[ ! "$extension_id" =~ ^[a-z]{32}$ ]]; then
        print_error "Invalid extension ID format"
        echo "  The ID should be 32 lowercase letters"
        echo "  Example: klklanpnnikhmbafjiecpecafcgdpknh"
        exit 1
    fi

    print_success "Extension ID: $extension_id"
    echo ""
}

install_native_host() {
    print_step "Installing native messaging host..."

    # Create target directory
    mkdir -p "$NATIVE_HOST_TARGET"

    # Make host script executable
    chmod +x "$NATIVE_HOST_DIR/gamdl_host.py"

    # Write manifest with correct path and extension ID
    local manifest_file="$NATIVE_HOST_TARGET/$HOST_NAME.json"

    cat > "$manifest_file" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native messaging host for gamdl Chrome extension",
  "path": "$NATIVE_HOST_DIR/gamdl_host.py",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$extension_id/"
  ]
}
EOF

    print_success "Native host manifest: $manifest_file"
    print_success "Host script: $NATIVE_HOST_DIR/gamdl_host.py"
    echo ""
}

setup_lossless() {
    print_step "Lossless (ALAC) support (optional)..."

    echo ""
    echo "  ALAC downloads require additional setup:"
    echo "  - Docker running with the wrapper container"
    echo "  - mp4decrypt (from Bento4)"
    echo "  - amdecrypt binary"
    echo ""

    read -p "  Set up lossless support? (y/N): " setup_alac

    if [[ ! "$setup_alac" =~ ^[Yy]$ ]]; then
        print_info "Skipping lossless setup"
        return
    fi

    # Check Bento4/mp4decrypt
    if command -v mp4decrypt &> /dev/null; then
        print_success "mp4decrypt found"
    else
        print_warning "mp4decrypt not found"
        if [[ "$OS" == "macos" ]]; then
            read -p "  Install Bento4 via Homebrew? (Y/n): " install_bento
            if [[ ! "$install_bento" =~ ^[Nn]$ ]]; then
                brew install bento4
                print_success "Bento4 installed"
            fi
        else
            print_info "Install Bento4 from: https://www.bento4.com/downloads/"
        fi
    fi

    # Check Docker
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            print_success "Docker is running"
        else
            print_warning "Docker is installed but not running"
            print_info "Start Docker Desktop to use lossless downloads"
        fi
    else
        print_warning "Docker not found"
        print_info "Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
    fi

    echo ""
}

print_completion() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Setup Complete!${NC}                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  ${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. ${YELLOW}Restart Chrome completely${NC} (Cmd+Q on macOS)"
    echo "  2. Navigate to ${CYAN}music.apple.com${NC}"
    echo "  3. Click the gamdl extension icon"
    echo "  4. Select tracks and click Download!"
    echo ""
    echo "  ${BOLD}Tips:${NC}"
    echo "  • Toggle ${CYAN}Lossless (ALAC)${NC} for higher quality (requires wrapper)"
    echo "  • Albums already downloaded will show a green checkmark"
    echo "  • Progress is shown during downloads"
    echo ""
    echo "  ${BOLD}Troubleshooting:${NC}"
    echo "  • Check the browser console for errors (F12 → Console)"
    echo "  • Make sure cookies.txt is valid and not expired"
    echo "  • For lossless, ensure Docker wrapper is running"
    echo ""
}

# Main flow
print_header

echo "This utility will help you set up the gamdl Chrome extension."
echo "It will check dependencies, configure settings, and install the native host."
echo ""
read -p "Press Enter to continue..."
echo ""

check_dependencies
setup_config
install_extension
install_native_host
setup_lossless
print_completion
