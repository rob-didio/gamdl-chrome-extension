#!/bin/bash
#
# Install script for gamdl Chrome extension native messaging host
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_NAME="com.gamdl.host"
EXTENSION_DIR="$(dirname "$SCRIPT_DIR")"

# Detect OS and set target directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
else
    echo "Error: Unsupported operating system: $OSTYPE"
    exit 1
fi

echo "Installing gamdl native messaging host..."
echo ""

# Check if extension ID was provided as argument
EXTENSION_ID="$1"

if [[ -z "$EXTENSION_ID" ]]; then
    echo "Chrome requires the exact extension ID for native messaging."
    echo ""
    echo "To get the extension ID:"
    echo "  1. Open Chrome and go to chrome://extensions"
    echo "  2. Enable 'Developer mode' (toggle in top right)"
    echo "  3. Click 'Load unpacked' and select: $EXTENSION_DIR"
    echo "  4. Copy the 32-character ID shown under the extension name"
    echo ""
    read -p "Enter extension ID: " EXTENSION_ID
    echo ""
fi

# Validate extension ID format (32 lowercase letters)
if [[ ! "$EXTENSION_ID" =~ ^[a-z]{32}$ ]]; then
    echo "Error: Invalid extension ID format."
    echo "The ID should be 32 lowercase letters (e.g., klklanpnnikhmbafjiecpecafcgdpknh)"
    exit 1
fi

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Make the host script executable
chmod +x "$SCRIPT_DIR/gamdl_host.py"

# Update the manifest with the correct path and extension ID
HOST_PATH="$SCRIPT_DIR/gamdl_host.py"
MANIFEST_FILE="$TARGET_DIR/$HOST_NAME.json"

cat > "$MANIFEST_FILE" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native messaging host for gamdl Chrome extension",
  "path": "$HOST_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF

echo "Native messaging host installed successfully!"
echo ""
echo "Manifest location: $MANIFEST_FILE"
echo "Host script: $HOST_PATH"
echo "Extension ID: $EXTENSION_ID"
echo ""
echo "Next steps:"
echo "1. Quit Chrome completely (Cmd+Q on macOS, or fully close on Linux)"
echo "2. Reopen Chrome"
echo "3. Navigate to any Apple Music page and click the extension icon"
echo ""
