#!/bin/bash
INSTALL_PATH="/usr/local/bin/update-haproxy"

echo "🔄 Installing update-haproxy..."

curl -sL https://raw.githubusercontent.com/hamedp6/haproxy-config-tool/main/update_haproxy.sh -o "$INSTALL_PATH"

chmod +x "$INSTALL_PATH"

echo "✅ Installation complete! Run with: sudo update-haproxy"
