#!/bin/bash
# Atlantis Travel Router - WAN/LAN manager
# Detects upstream (eth0, eth1, wlan1), rebuilds LAN bridge, sets up NAT.

set -e

WAN=""
LAN_IF=""
LOGFILE="/var/log/atlantis-status.log"
STATEFILE="/tmp/atlantis-lastwan"

# Kill any leftover DHCP clients
pkill dhclient 2>/dev/null || true

# Try eth0 first (hotel Ethernet)
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

# Load last WAN state
LASTWAN="none"
if [ -f "$STATEFILE" ]; then
    LASTWAN=$(cat "$STATEFILE")
fi

# If WAN hasn’t changed, just exit quietly
if [ "$WAN" = "$LASTWAN" ]; then
    exit 0
fi

# Save new state
echo "$WAN" > "$STATEFILE"

# Clear iptables
iptables -t nat -F
iptables -F
iptables -X

# Rebuild bridge
ip link del br0 2>/dev/null || true
ip link add name br0 type bridge
ip link set wlan0 master br0
for i in $LAN_IF; do
    ip link set $i master br0
done
ip addr add 192.168.1.1/24 dev br0 || true
ip link set br0 up

# NAT Atlantis → WAN if WAN found
if [ "$WAN" != "none" ]; then
    iptables -t nat -A POSTROUTING -o $WAN -j MASQUERADE
    iptables -A FORWARD -i br0 -o $WAN -j ACCEPT
    iptables -A FORWARD -i $WAN -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
fi
# Redirect all DNS (UDP/TCP port 53) from 192.168.1.8 → 192.168.1.1
iptables -t nat -A PREROUTING -d 192.168.1.8 -p udp --dport 53 -j DNAT --to-destination 192.168.1.1
iptables -t nat -A PREROUTING -d 192.168.1.8 -p tcp --dport 53 -j DNAT --to-destination 192.168.1.1

# Save for OLED
echo "$WAN" > /tmp/atlantis-wan
echo "$LAN_IF" > /tmp/atlantis-lan

# Log WAN/LAN change
TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "$TS [Atlantis] WAN changed to $WAN, LAN = $LAN_IF" | sudo tee -a "$LOGFILE" >/dev/null

# Captive portal control
if [ "$WAN" = "none" ]; then
    systemctl start portal
else
    systemctl stop portal
fi

# Auto Channel Selection
if [ "$WAN" != "none" ]; then
    /usr/local/bin/choose-channel.sh
else
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TS [Atlantis] AP started on channel 6 (no WAN, fallback)" | sudo tee -a "$LOGFILE" >/dev/null
fi
