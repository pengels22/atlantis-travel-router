#!/bin/bash
# Atlantis Travel Router - Auto Channel Picker
# Chooses least crowded 2.4GHz channel (1, 6, 11) and logs it

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
LOGFILE="/var/log/atlantis-status.log"

echo "[Atlantis] Scanning Wi-Fi environment..."
SCAN=$(iwlist wlan1 scan 2>/dev/null)

if [ -z "$SCAN" ]; then
    echo "[Atlantis] Scan failed. Falling back to channel 6."
    BEST=6
else
    # Count APs per channel
    count_chan() {
        echo "$SCAN" | grep "Channel:$1" | wc -l
    }

    C1=$(count_chan 1)
    C6=$(count_chan 6)
    C11=$(count_chan 11)

    echo "[Atlantis] Detected APs -> Ch1: $C1, Ch6: $C6, Ch11: $C11"

    # Pick channel with lowest count (default = 6 if tie)
    BEST=6
    if [ "$C1" -le "$C6" ] && [ "$C1" -le "$C11" ]; then
        BEST=1
    elif [ "$C6" -le "$C1" ] && [ "$C6" -le "$C11" ]; then
        BEST=6
    else
        BEST=11
    fi
fi

echo "[Atlantis] Choosing channel $BEST"

# Rewrite hostapd.conf (preserve everything except channel line)
if grep -q "^channel=" "$HOSTAPD_CONF"; then
    sudo sed -i "s/^channel=.*/channel=$BEST/" "$HOSTAPD_CONF"
else
    echo "channel=$BEST" | sudo tee -a "$HOSTAPD_CONF" >/dev/null
fi

# Restart hostapd with new channel
echo "[Atlantis] Restarting hostapd..."
sudo systemctl restart hostapd

# Log the result
TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "$TS [Atlantis] AP started on channel $BEST" | sudo tee -a "$LOGFILE" >/dev/null
