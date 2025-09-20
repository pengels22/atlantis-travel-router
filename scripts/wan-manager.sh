#!/bin/bash
# Atlantis Travel Router - WAN/LAN Manager
# Detects upstream (eth0, eth1, wlan1), builds LAN bridge, sets up NAT.
# Also controls captive portal service when no WAN is detected.

set -euo pipefail

WAN=""
LAN_IF=""

# Kill any leftover DHCP clients
pkill dhclient 2>/dev/null || true

# === Detect WAN ===
if dhclient -1 eth0; then
    WAN="eth0"
    LAN_IF="eth1"
elif dhclient -1 eth1; then
    WAN="eth1"
    LAN_IF="eth0"
elif dhclient -1 wlan1; then
    WAN="wlan1"
    LAN_IF="eth0 eth1"
else
    WAN="none"
    LAN_IF="eth0 eth1"
fi

# === Reset iptables ===
iptables -t nat -F
iptables -F
iptables -X

# === Rebuild Atlantis bridge ===
ip link del br0 2>/dev/null || true
ip link add name br0 type bridge

# Detach any previous masters to avoid duplicates
ip link set wlan0 nomaster 2>/dev/null || true
for i in $LAN_IF; do
    ip link set $i nomaster 2>/dev/null || true
done

# Add LAN interfaces to bridge
ip link set wlan0 master br0
for i in $LAN_IF; do
    ip link set $i master br0
done

# Assign Atlantis LAN IP
ip addr flush dev br0 || true
ip addr add 192.168.1.1/24 dev br0 || true
ip link set br0 up

# === NAT Atlantis → WAN if WAN found ===
if [ "$WAN" != "none" ]; then
    iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE
    iptables -A FORWARD -i br0 -o "$WAN" -j ACCEPT
    iptables -A FORWARD -i "$WAN" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
fi

# === Save state for OLED ===
echo "$WAN" > /tmp/atlantis-wan
echo "$LAN_IF" > /tmp/atlantis-lan

echo "[Atlantis] WAN = $WAN, LAN = $LAN_IF"

# === Portal control ===
if [ "$WAN" = "none" ]; then
    systemctl start portal
else
    systemctl stop portal
fi
