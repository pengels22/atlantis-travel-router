#!/bin/bash
# Atlantis Router Setup Script (Unattended)
# Handles repo clone/update, dependency install, service setup.
# Supports --dev mode to skip Pi-hole + Tailscale installs
# Logs everything to /var/log/atlantis-setup-<timestamp>.log

set -euo pipefail

REPO_URL="https://github.com/pengels22/atlantis-travel-router.git"
REPO_DIR="$HOME/atlantis-travel-router"

LOG_DIR="/var/log"
TIMESTAMP=$(date +"%Y%m%d-%H%M")
LOG_FILE="$LOG_DIR/atlantis-setup-$TIMESTAMP.log"

SERVICES=(
  wan-manager
  wan-manager.timer
  oled-status
  portal
  captive-watchdog
  hostapd
  dnsmasq
)

DEV_MODE=false
if [[ "${1:-}" == "--dev" ]]; then
    DEV_MODE=true
    echo "=== [Atlantis] Running in DEV MODE (skipping Pi-hole + Tailscale) ==="
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root: sudo ./setup.sh [--dev]"
    exit 1
fi

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== [Atlantis] Setup started at $(date) ==="
echo "Logging to $LOG_FILE"

echo "=== [Atlantis] Updating system packages ==="
apt-get update
apt-get -o Dpkg::Options::="--force-confold" upgrade -y

echo "=== [Atlantis] Installing dependencies ==="
apt-get install -y \
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

if [ "$DEV_MODE" = false ]; then
    echo "=== [Atlantis] Installing Tailscale ==="
    curl -fsSL https://tailscale.com/install.sh | sh || {
        echo "[Atlantis] ERROR: Tailscale install failed."
    }

    echo "=== [Atlantis] Installing Pi-hole (unattended) ==="
    curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended || {
        echo "[Atlantis] ERROR: Pi-hole install failed."
    }
else
    echo "=== [Atlantis] Skipping Tailscale + Pi-hole installs (DEV MODE) ==="
fi

echo "=== [Atlantis] Cloning/Updating repo ==="
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    git pull
else
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

echo "=== [Atlantis] Deploying configs ==="
mkdir -p /etc/atlantis
cp config/hostapd.conf /etc/hostapd/hostapd.conf
cp config/dnsmasq.conf /etc/dnsmasq.conf
cp config/dhcpcd.conf /etc/dhcpcd.conf

echo "=== [Atlantis] Deploying scripts ==="
install -m 755 scripts/wan-manager.sh /usr/local/bin/wan-manager.sh
install -m 755 scripts/choose-channel.sh /usr/local/bin/choose-channel.sh
install -m 755 oled/oled-status.py /usr/local/bin/oled-status.py
install -m 755 portal/portal.py /usr/local/bin/portal.py
install -m 755 scripts/captive-watchdog.sh /usr/local/bin/captive-watchdog.sh

echo "=== [Atlantis] Deploying services ==="
cp services/*.service /etc/systemd/system/
systemctl daemon-reload

echo "=== [Atlantis] Disabling dhcpcd (using dhclient in wan-manager) ==="
systemctl stop dhcpcd || true
systemctl disable dhcpcd || true

echo "=== [Atlantis] Preparing log directories ==="
mkdir -p /var/log/atlantis-history
touch /var/log/atlantis-status.log

echo "=== [Atlantis] Enabling & starting services ==="
FAILED_SERVICES=()
for svc in "${SERVICES[@]}"; do
    systemctl enable "$svc" || true
    systemctl restart "$svc" || true
    if systemctl is-active --quiet "$svc"; then
        echo "[OK] $svc is running"
    else
        echo "[ERROR] $svc is NOT running"
        FAILED_SERVICES+=("$svc")
    fi
done

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "=== [Atlantis] Some services failed: ${FAILED_SERVICES[*]} ==="
else
    echo "=== [Atlantis] All services running successfully ==="
fi

echo "=== [Atlantis] Setup finished at $(date) ==="
echo "Log saved to $LOG_FILE"
echo "Reboot manually when ready."
