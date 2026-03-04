#!/bin/bash

# Function to display help
show_help() {
    echo "Usage:"
    echo "  Interactive mode: ./script.sh"
    echo "  Inline mode:      ./script.sh <domain> <port>"
    echo ""
    echo "Example:"
    echo "  ./script.sh google.com 8443"
    exit 0
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Get values from user (interactive or inline)
if [ $# -eq 2 ]; then
    DOMAIN="$1"
    PORT="$2"
    echo "Using inline mode - Domain: $DOMAIN, Port: $PORT"
else
    echo "Enter PORT:"
    read PORT
    echo "Enter domain:"
    read DOMAIN
fi

# Validate inputs
if [ -z "$PORT" ] || [ -z "$DOMAIN" ]; then
    echo "Error: PORT and DOMAIN cannot be empty"
    exit 1
fi

# Fixed UUID
UUID="c90b0c48-5ed6-4780-9e47-0bdf091e7f4c"

# Update package list and install dependencies
echo "Installing dependencies..."
apt update
apt install -y wget curl unzip

# Install Xray core
echo "Installing Xray core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Create Xray config
echo "Creating Xray configuration..."
cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "header": {
            "type": "http"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# Restart Xray
echo "Restarting Xray..."
systemctl restart xray
systemctl enable xray

# Download dnstt-server
echo "Downloading dnstt-server..."
wget -O /tmp/dnstt-server https://github.com/crashmoneysite/dns/raw/refs/heads/main/dnstt-server
chmod +x /tmp/dnstt-server
mv /tmp/dnstt-server /usr/local/bin/dnstt-server

# Generate keys
echo "Generating dnstt keys..."
cd /usr/local/bin
./dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub

# Get server keys
SERVER_KEY=$(cat server.key)
PUBLIC_KEY=$(cat server.pub)

# Create systemd service for dnstt
echo "Creating dnstt service..."
cat > /etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT Tunnel Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey ${SERVER_KEY} ${DOMAIN} 127.0.0.1:${PORT}
Restart=always
RestartSec=3
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

# Start dnstt service
echo "Starting dnstt service..."
systemctl daemon-reload
systemctl start dnstt
systemctl enable dnstt

# Check if services are running
echo "Checking services..."
sleep 2

XRAY_STATUS=$(systemctl is-active xray)
DNSTT_STATUS=$(systemctl is-active dnstt)

if [ "$XRAY_STATUS" = "active" ] && [ "$DNSTT_STATUS" = "active" ]; then
    echo ""
    echo "===================================================="
    echo "✅ Installation completed successfully!"
    echo "===================================================="
    echo ""
    echo "V2RAY:"
    echo "vless://${UUID}@127.0.0.1:${PORT}?security=none&encryption=none&headerType=http&type=tcp#Server"
    echo ""
    echo "DNSTT:"
    echo "dns://${DOMAIN}@${PUBLIC_KEY}"
    echo ""
    echo "===================================================="
else
    echo ""
    echo "⚠️  Installation completed but some services are not running."
    echo "Xray status: $XRAY_STATUS"
    echo "DNSTT status: $DNSTT_STATUS"
    echo ""
    echo "Please check the logs:"
    echo "  journalctl -u xray -xe"
    echo "  journalctl -u dnstt -xe"
fi

echo ""
echo "Service management commands:"
echo "  systemctl status xray    - Check Xray status"
echo "  systemctl status dnstt   - Check DNSTT status"
echo "  systemctl restart dnstt  - Restart DNSTT service"
echo "  journalctl -u dnstt -f   - View DNSTT logs"
