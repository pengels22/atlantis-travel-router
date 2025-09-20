#!/usr/bin/env python3
# Atlantis OLED Status Display
# Normal: WAN IP / WAN Port / LAN Ports / Clients
# Offline: Access Point Mode / Config IP / PIN

import time
import subprocess
from luma.core.interface.serial import i2c
from luma.oled.device import sh1106
from PIL import Image, ImageDraw, ImageFont

# === OLED setup ===
serial = i2c(port=1, address=0x3C)
device = sh1106(serial)
font = ImageFont.load_default()

CONFIG_PIN = "0831"  # Hard-coded configuration PIN

def get_file_value(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except:
        return "N/A"

def get_client_count():
    try:
        out = subprocess.check_output("arp -n | grep br0 | wc -l", shell=True)
        return out.decode().strip()
    except:
        return "0"

def get_wan_ip(wan_if):
    if wan_if in ("N/A", "none", ""):
        return ""
    try:
        out = subprocess.check_output(
            f"ip -4 addr show {wan_if} | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'",
            shell=True
        )
        return out.decode().strip()
    except:
        return ""

while True:
    wan_if = get_file_value("/tmp/atlantis-wan")
    lan_if = get_file_value("/tmp/atlantis-lan")
    clients = get_client_count()
    wan_ip = get_wan_ip(wan_if)

    img = Image.new("1", device.size, "black")
    draw = ImageDraw.Draw(img)

    if wan_if in ("none", "N/A", "") or wan_ip == "":
        # === Access Point Mode ===
        draw.text((0, 0), "Access Point Mode", font=font, fill=255)
        draw.text((0, 12), "Config IP: 192.168.1.1", font=font, fill=255)
        draw.text((0, 24), f"PIN: {CONFIG_PIN}", font=font, fill=255)
    else:
        # === Normal Mode ===
        draw.text((0, 0),  f"WAN IP: {wan_ip}", font=font, fill=255)
        draw.text((0, 12), f"WAN: {wan_if}", font=font, fill=255)
        draw.text((0, 24), f"LAN: {lan_if}", font=font, fill=255)
        draw.text((0, 36), f"Clients: {clients}", font=font, fill=255)

    device.display(img)
    time.sleep(5)
