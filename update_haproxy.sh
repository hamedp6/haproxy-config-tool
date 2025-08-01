#!/bin/bash

# 🎨 Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
TMP_FILE=$(mktemp)
BACKUP_FILE="${HAPROXY_CFG}.bak"

echo -e "${CYAN}🔄 Checking and installing HAProxy...${RESET}"
sudo apt update -y && sudo apt install -y haproxy

if [ -f "$HAPROXY_CFG" ]; then
    sudo cp "$HAPROXY_CFG" "$BACKUP_FILE"
    echo -e "${YELLOW}📦 Backup created at ${BACKUP_FILE}${RESET}"
fi

echo -e "${CYAN}📜 Current configured ports:${RESET}"
if [ -f "$HAPROXY_CFG" ]; then
    EXISTING_PORTS=$(grep -E "frontend frontend_" "$HAPROXY_CFG" | awk '{print $2}' | sed 's/frontend_//' | sort -n)
    if [ -z "$EXISTING_PORTS" ]; then
        echo -e "${YELLOW}⚠️ No frontend ports configured yet.${RESET}"
    else
        echo "$EXISTING_PORTS"
    fi
else
    echo -e "${RED}❌ No haproxy.cfg file found yet.${RESET}"
fi
echo "------------------------------------"

read -r -d '' STATIC_CONFIG << 'EOF'
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
EOF

echo -e "${CYAN}What do you want to do?${RESET}"
echo "1) ➕ Add new ports"
echo "2) ➖ Remove existing ports"
read -p "Enter choice (1/2): " ACTION

# 🔹 Extract only existing frontend/backend blocks
grep -E "^(frontend|backend)" -A 5 "$HAPROXY_CFG" 2>/dev/null > "$TMP_FILE"

if [[ "$ACTION" == "1" ]]; then
    read -p "Enter the server IP: " SERVER_IP
    read -p "Enter ports separated by spaces (e.g. 9080 9180 9280): " -a PORTS
    read -p "Use IPv4 or IPv6 bind? (4/6): " BIND_TYPE

    if [[ "$BIND_TYPE" == "6" ]]; then
        BIND_CMD="    bind *:PORT\n    bind :::PORT"
    else
        BIND_CMD="    bind *:PORT"
    fi

    for PORT in "${PORTS[@]}"; do
        if grep -q "frontend frontend_${PORT}" "$TMP_FILE"; then
            echo -e "${YELLOW}⚠️ Skipping port $PORT (already exists)${RESET}"
            continue
        fi
        BIND_LINES=$(echo -e "$BIND_CMD" | sed "s/PORT/$PORT/g")
        cat <<EOL >> "$TMP_FILE"

frontend frontend_${PORT}
${BIND_LINES}
    default_backend backend_${PORT}

backend backend_${PORT}
    server server_${PORT} ${SERVER_IP}:${PORT}
EOL
        echo -e "${GREEN}✅ Added port $PORT${RESET}"
    done

elif [[ "$ACTION" == "2" ]]; then
    read -p "Enter ports to remove (e.g. 9080 9180): " -a REMOVE_PORTS

    for PORT in "${REMOVE_PORTS[@]}"; do
        sed -i "/^frontend frontend_${PORT}/,/^$/d" "$TMP_FILE"
        sed -i "/^backend backend_${PORT}/,/^$/d" "$TMP_FILE"
        echo -e "${GREEN}✅ Removed port $PORT${RESET}"
    done
fi

# 🔹 Rebuild final config
{
    echo "$STATIC_CONFIG"
    cat "$TMP_FILE"
} | sudo tee "$HAPROXY_CFG" > /dev/null

rm -f "$TMP_FILE"

# 🔹 Validate config
echo -e "${CYAN}🔍 Validating HAProxy config...${RESET}"
if sudo haproxy -c -f "$HAPROXY_CFG"; then
    echo -e "${GREEN}✅ Config is valid!${RESET}"
    sudo systemctl enable haproxy
    sudo systemctl restart haproxy
    echo -e "${GREEN}✅ HAProxy restarted and enabled at boot!${RESET}"
else
    echo -e "${RED}❌ Config validation failed! Restoring backup...${RESET}"
    sudo cp "$BACKUP_FILE" "$HAPROXY_CFG"
    sudo systemctl restart haproxy
    echo -e "${YELLOW}🔄 HAProxy restored to previous working config.${RESET}"
fi
