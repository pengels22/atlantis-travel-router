#!/bin/bash
# Atlantis status logger
# Writes JSON lines to /var/log/atlantis-status.log
# Usage:
#   atlantis-logger.sh            # record status (no speedtest)
#   atlantis-logger.sh --speed    # run speedtest (slow, uses bandwidth)
#   atlantis-logger.sh --once     # run once (same as no args)
#
# Requires: ip, awk, grep, curl, jq (jq optional but recommended), arp, iw, iwgetid, python3 (optional)
set -euo pipefail

LOG_FILE="/var/log/atlantis-status.log"
PIHOLE_API="http://127.0.0.1/admin/api.php?summary"  # local Pi-hole
SPEEDTEST=false

# parse args
for arg in "$@"; do
  case "$arg" in
    --speed|--speedtest|-s) SPEEDTEST=true ;;
    --once) ;; # noop
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# read WAN/LAN from wan-manager outputs
WAN_IF=$(cat /tmp/atlantis-wan 2>/dev/null || echo "none")
LAN_IFACES=$(cat /tmp/atlantis-lan 2>/dev/null || echo "eth0 eth1")

# helper to get IPv4 addr for interface
get_ip() {
  iface="$1"
  ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 || echo ""
}

# helper to get default gateway for interface
get_gateway() {
  iface="$1"
  ip route | awk -v dev="$iface" '$0 ~ "default" && $0 ~ dev { for(i=1;i<=NF;i++){ if($i=="via"){print $(i+1); exit}} }' || echo ""
}

# helper to get MAC for an IP from ARP table or via ping+arp
mac_for_ip() {
  ipaddr="$1"
  if [ -z "$ipaddr" ]; then echo ""; return; fi
  # try arp table
  mac=$(ip neigh show "$ipaddr" 2>/dev/null | awk '{print $5; exit}' || true)
  if [ -n "$mac" ] && [ "$mac" != "(incomplete)" ]; then echo "$mac"; return; fi
  # ping to populate
  ping -c 1 -W 1 "$ipaddr" >/dev/null 2>&1 || true
  mac=$(ip neigh show "$ipaddr" 2>/dev/null | awk '{print $5; exit}' || true)
  echo "${mac:-}"
}

# Wi-Fi specifics (for wlan1 as WAN)
get_wifi_ssid() {
  iface="$1"
  if [ -z "$iface" ]; then echo ""; return; fi
  iwgetid "$iface" -r 2>/dev/null || echo ""
}
get_wifi_bssid() {
  iface="$1"
  if [ -z "$iface" ]; then echo ""; return; fi
  iw dev "$iface" link 2>/dev/null | awk -F': ' '/Connected to/ {print $2; exit}' || echo ""
}

# clients count (ARP + station)
client_count() {
  # ARP table entries on br0
  arp_count=$(arp -n | awk '/br0/ {count++} END{print count+0}')
  # station dump count (wireless clients)
  sta_count=0
  if command -v iw >/dev/null 2>&1; then
    out=$(iw dev wlan0 station dump 2>/dev/null || true)
    sta_count=$(grep -c '^Station ' <<<"$out" || true)
  fi
  # prefer station count if > arp, otherwise arp_count
  if [ "$sta_count" -gt 0 ]; then
    echo "$sta_count"
  else
    echo "$arp_count"
  fi
}

# pi-hole summary (safe: returns minimal fields)
get_pihole_summary() {
  if curl -s --max-time 3 "$PIHOLE_API" >/dev/null 2>&1; then
    # try to get JSON; jq optional
    if command -v jq >/dev/null 2>&1; then
      curl -s --max-time 3 "$PIHOLE_API" | jq '{dns_queries_today,ads_blocked_today,ads_percentage_today,unique_clients}' || echo "{}"
    else
      # parse minimally without jq
      out=$(curl -s --max-time 3 "$PIHOLE_API" || echo "{}")
      # try to extract numeric fields using grep -Po
      dns=$(grep -Po '"dns_queries_today":\s*\K[0-9]+' <<<"$out" || echo 0)
      ads=$(grep -Po '"ads_blocked_today":\s*\K[0-9]+' <<<"$out" || echo 0)
      pct=$(grep -Po '"ads_percentage_today":\s*\K[0-9]+' <<<"$out" || echo 0)
      clients=$(grep -Po '"unique_clients":\s*\K[0-9]+' <<<"$out" || echo 0)
      printf '{"dns_queries_today":%s,"ads_blocked_today":%s,"ads_percentage_today":%s,"unique_clients":%s}' "$dns" "$ads" "$pct" "$clients"
    fi
  else
    echo "{}"
  fi
}

# optional speedtest (uses speedtest-cli)
run_speedtest() {
  # prefer speedtest CLI if installed
  if command -v speedtest >/dev/null 2>&1; then
    # Ookla official CLI: speedtest --format=json
    speedtest --format=json 2>/dev/null || echo "{}"
  elif command -v speedtest-cli >/dev/null 2>&1; then
    # python speedtest-cli (may be slower) - use --json
    speedtest-cli --json 2>/dev/null || echo "{}"
  elif command -v pip3 >/dev/null 2>&1; then
    # try to install speedtest-cli minimally
    pip3 install --break-system-packages --quiet speedtest-cli || true
    if command -v speedtest-cli >/dev/null 2>&1; then
      speedtest-cli --json 2>/dev/null || echo "{}"
    else
      echo "{}"
    fi
  else
    echo "{}"
  fi
}

# gather data
TS=$(timestamp)
MODE="unknown"
WAN_IP=""
WAN_GATEWAY=""
WAN_GATEWAY_MAC=""
WIFI_SSID=""
WIFI_BSSID=""
CLIENTS=$(client_count)
PIHOLE_JSON="$(get_pihole_summary)"
SPEED_JSON="{}"

if [ "$WAN_IF" = "none" ] || [ -z "$WAN_IF" ]; then
  MODE="ap"
else
  MODE="upstream"
  WAN_IP=$(get_ip "$WAN_IF")
  # gateway and mac for ethernet if present
  WAN_GATEWAY=$(get_gateway "$WAN_IF")
  WAN_GATEWAY_MAC=$(mac_for_ip "$WAN_GATEWAY")

  if [[ "$WAN_IF" == wlan* ]]; then
    WIFI_SSID=$(get_wifi_ssid "$WAN_IF")
    WIFI_BSSID=$(get_wifi_bssid "$WAN_IF")
  fi

  # optionally run speedtest
  if [ "$SPEEDTEST" = true ]; then
    SPEED_JSON="$(run_speedtest)"
  fi
fi

# build a JSON line (safe quoting)
# We'll include fields: ts, mode, wan_iface, wan_ip, gateway, gateway_mac, wifi_ssid, wifi_bssid, lan_ifaces, clients, pihole, speed
# pihole and speed are nested JSON strings
pihole_escaped=$(sed 's/"/\\"/g' <<<"$PIHOLE_JSON")
speed_escaped=$(sed 's/"/\\"/g' <<<"$SPEED_JSON")

json_line=$(cat <<EOF
{
  "ts":"$TS",
  "mode":"$MODE",
  "wan_iface":"$WAN_IF",
  "wan_ip":"$WAN_IP",
  "gateway":"$WAN_GATEWAY",
  "gateway_mac":"$WAN_GATEWAY_MAC",
  "wifi_ssid":"$WIFI_SSID",
  "wifi_bssid":"$WIFI_BSSID",
  "lan_ifaces":"$LAN_IFACES",
  "clients":$CLIENTS,
  "pihole":$PIHOLE_JSON,
  "speed":$SPEED_JSON
}
EOF
)

# append as one line (compact)
echo "$json_line" | jq -c . 2>/dev/null >> "$LOG_FILE" || (python3 - <<PY
import json,sys
print(json.dumps(json.loads(sys.stdin.read().strip())))
PY <<<"$json_line" >> "$LOG_FILE" 2>/dev/null || echo "$json_line" >> "$LOG_FILE"

# also optionally print the line to stdout
echo "Logged status at $TS to $LOG_FILE"
