#!/bin/bash
# Atlantis Captive Portal Watchdog
# Detects captive portal situations and triggers OS popup
# Run as a systemd service

CHECK_HOST="http://captive.apple.com"
EXPECTED_CONTENT="Success"
WAN_IF=$(cat /tmp/atlantis-wan 2>/dev/null || echo "none")

while true; do
    if [ "$WAN_IF" != "none" ]; then
        # Try to fetch the known endpoint
        CONTENT=$(curl -s --interface "$WAN_IF" --max-time 5 "$CHECK_HOST" || echo "")

        if [[ "$CONTENT" != *"$EXPECTED_CONTENT"* ]]; then
            echo "[Atlantis] Captive portal detected on $WAN_IF"

            # Option 1: force DNS redirect for LAN clients
            iptables -t nat -A PREROUTING -i br0 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.1:8080

            # Option 2: log + notify OLED
            echo "CAPTIVE" > /tmp/atlantis-status

            # Once hotel login completes, the check will succeed and rules can be cleared
        else
            # Remove captive portal redirect if internet is open
            iptables -t nat -D PREROUTING -i br0 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.1:8080 2>/dev/null || true
            echo "OK" > /tmp/atlantis-status
        fi
    fi
    sleep 30
done
