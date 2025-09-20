#!/bin/bash
# Atlantis Router Setup Script
# Installs dependencies, deploys configs, enables services.
# Run this as root:  sudo ./setup.sh

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo ./setup.sh)"
    exit 1
fi

echo "=== [Atlantis] Updating system packages ==="
apt update && apt upgrade -y

echo "=== [Atlantis] Installing core dependencies ==="
apt install -y \
    hostapd \
    dnsmasq \
    git \
    python3-pip \
    python3-dev \
    python3-venv \
    net-tools \
    iptables \
    bridge-utils \
    curl \
    unzip \
    wget \
    pkg-config \
    libfreetype6-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    libtiff5 \
    libatlas-base-dev \
    i2c-tools \
    python3-smbus \
    raspi-config

echo "=== [Atlantis] Installing Python packages ==="
pip3 install --break-system-packages \
    pillow \
    netifaces \
    requests \
    luma.oled \
    flask

echo "=== [Atlantis] Installing Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh || {
    echo "[Atlantis] ERROR: Tailscale install failed."
    exit 1
}

echo "=== [Atlantis] Installing Pi-hole (unattended) ==="
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended || {
    echo "[Atlantis] ERROR: Pi-hole install failed."
    exit 1
}

echo "=== [Atlantis] Deploying configs ==="
mkdir -p /etc/atlantis
cp ../config/hostapd.conf /etc/hostapd/hostapd.conf
cp ../config/dnsmasq.conf /etc/dnsmasq.conf
cp ../config/dhcpcd.conf /etc/dhcpcd.conf

echo "=== [Atlantis] Deploying scripts ==="
cp wan-manager.sh /usr/local/bin/wan-manager.sh
chmod +x /usr/local/bin/wan-manager.sh

echo "=== [Atlantis] Deploying OLED + Portal ==="
cp ../oled/oled-status.py /usr/local/bin/oled-status.py
chmod +x /usr/local/bin/oled-status.py
cp ../portal/portal.py /usr/local/bin/portal.py
chmod +x /usr/local/bin/portal.py

echo "=== [Atlantis] Deploying services ==="
cp ../services/*.service /etc/systemd/system/
systemctl daemon-reload

echo "=== [Atlantis] Enabling services ==="
systemctl enable hostapd dnsmasq wan-manager oled-status
systemctl start hostapd dnsmasq wan-manager oled-status

echo "=== [Atlantis] Setup complete! ==="
echo "Reboot is strongly recommended: sudo reboot"
