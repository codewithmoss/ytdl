#!/bin/bash

# Install ytdl to /usr/local/bin

set -e

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="ytdl"
REPO_URL="https://raw.githubusercontent.com/codewithmoss/ytdl/main/ytdl.sh"

echo "Downloading ytdl..."
curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo "✅ ytdl installed successfully at $INSTALL_DIR/$SCRIPT_NAME"

