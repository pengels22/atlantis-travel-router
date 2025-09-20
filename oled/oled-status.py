#!/usr/bin/env python3
# Atlantis Router - OLED Status Display
# Shows WAN IP/port, LAN ports, client count
# Falls back to Access Point Mode + PIN when no WAN
# Integrates captive portal status

import time
import os
import socket
import subprocess
from luma.core.interface.serial import i2c
from luma.oled.device import sh1106
from PIL import ImageFont, ImageDraw, Image

# === Setup OLED ===
serial = i2c(port=1, address=0x3C)
device = sh1106(serial, rotate=0)
font = ImageFont.load_default()

# === Config ===
CONFIG_PIN = "0831"
REFRESH_INTERVAL = 5


def read_file(path, default=""):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return default


def get_ip_address(iface):
    try:
        result = subprocess.check_output(
            ["ip", "-4", "addr", "show", iface], stderr=subprocess.DEVNULL
        ).decode()
        for line in result.splitlines():
            line = line.strip()
            if line.startswith("inet "):
                return line.split()[1].split("/")[0]
    except subprocess.CalledProcessError:
        return "0.0.0.0"
    return "0.0.0.0"


def get_client_count():
    try:
        output = subprocess.check_output(
            ["iw", "dev", "wlan0", "station", "dump"], stderr=subprocess.DEVNULL
        ).decode()
        return output.count("Station ")
    except subprocess.CalledProcessError:
        return 0


def draw_lines(lines):
    with Image.new("1", device.size) as image:
        draw = ImageDraw.Draw(image)
        for i, line in enumerate(lines):
            draw.text((0, i * 12), line, font=font, fill=255)
        device.display(image)


def main():
    while True:
        wan_iface = read_file("/tmp/atlantis-wan", "none")
        lan_ifaces = read_file("/tmp/atlantis-lan", "")
        captive_status = read_file("/tmp/atlantis-status", "OK")

        if wan_iface == "none":
            # Access Point Mode
            lines = [
                "Access Point Mode",
                "Config: 192.168.1.1",
                f"PIN: {CONFIG_PIN}",
                f"Clients: {get_client_count()}",
            ]
        else:
            wan_ip = get_ip_address(wan_iface)
            if captive_status == "CAPTIVE":
                wan_line = f"WAN: {wan_iface} (CAPTIVE)"
            else:
                wan_line = f"WAN: {wan_ip}"

            lines = [
                wan_line,
                f"WAN Port: {wan_iface}",
                f"LAN: {lan_ifaces}",
                f"Clients: {get_client_count()}",
            ]

        draw_lines(lines)
        time.sleep(REFRESH_INTERVAL)


if __name__ == "__main__":
    main()
