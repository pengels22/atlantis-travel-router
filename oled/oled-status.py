#!/usr/bin/env python3
# Atlantis Router - OLED Status Display
# Pages:
# 1. WAN/LAN/Clients
# 2. Router info + shutdown hint
# 3. Last session summary averages
# 4. Live Pi-hole stats
# Short press = cycle page
# Medium press (>=5s <10s) = copy logs to USB
# Long press (>=10s) = shutdown with summary

import time
import glob
import json
import os
import subprocess
import requests
import RPi.GPIO as GPIO
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
MENU_BTN = 17          # BCM pin for menu button
HOLD_COPY = 5          # seconds for USB copy
HOLD_SHUTDOWN = 10     # seconds for shutdown
SUMMARY_DIR = "/var/log/atlantis-history"
PIHOLE_API = "http://127.0.0.1/admin/api.php?summary"

# === GPIO Setup ===
GPIO.setmode(GPIO.BCM)
GPIO.setup(MENU_BTN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

press_start = None
page_index = 0


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
    from PIL import Image
    with Image.new("1", device.size) as image:
        draw = ImageDraw.Draw(image)
        for i, line in enumerate(lines):
            draw.text((0, i * 12), line, font=font, fill=255)
        device.display(image)


def shutdown_sequence():
    # Step 1: Saving logs (1s)
    draw_lines(["Saving logs..."])
    time.sleep(1)

    # Run summary logger
    try:
        subprocess.call(["/usr/local/bin/atlantis-summarize.sh"])
    except Exception:
        pass

    # Step 2: Atlantis Shutdown (2s)
    draw_lines(["Atlantis Shutdown"])
    time.sleep(2)

    # Step 3: Power off
    subprocess.call(["shutdown", "-h", "now"])


def copy_logs_to_usb():
    draw_lines(["Copying logs...", "Searching USB..."])
    time.sleep(1)

    # Try common USB mount paths
    usb_mounts = ["/media", "/mnt", "/media/pi", "/media/usb", "/media/usb0", "/media/usb1"]
    target = None
    for base in usb_mounts:
        if not os.path.isdir(base):
            continue
        for entry in os.listdir(base):
            path = os.path.join(base, entry)
            if os.path.ismount(path):
                target = path
                break
        if target:
            break

    if not target:
        draw_lines(["No USB drive", "found!"])
        time.sleep(5)   # hold longer so user sees it
        return

    ts = time.strftime("%Y%m%d-%H%M")
    dest = os.path.join(target, f"atlantis-logs-{ts}")
    try:
        os.makedirs(dest, exist_ok=True)
        subprocess.call(["cp", "-r", "/var/log/atlantis-status.log", dest])
        subprocess.call(["cp", "-r", "/var/log/atlantis-history", dest])
        subprocess.call(["sync"])  # flush writes to USB
        draw_lines(["Logs copied OK", os.path.basename(target)])
    except Exception:
        draw_lines(["USB copy failed"])
    time.sleep(5)  # show result for 5s before returning


def check_button():
    global press_start, page_index
    if GPIO.input(MENU_BTN) == GPIO.LOW:  # pressed
        if press_start is None:
            press_start = time.time()
        else:
            held = time.time() - press_start
            if held >= HOLD_SHUTDOWN:
                shutdown_sequence()
            elif held >= HOLD_COPY:
                copy_logs_to_usb()
                press_start = None  # reset after copy
    else:
        if press_start is not None and (time.time() - press_start) < HOLD_COPY:
            # Short press → advance page
            page_index = (page_index + 1) % 4
        press_start = None


def load_last_summary():
    files = sorted(glob.glob(f"{SUMMARY_DIR}/atlantis-summary-*.json"))
    if not files:
        return None
    latest = files[-1]
    try:
        with open(latest, "r") as f:
            return json.load(f)
    except Exception:
        return None


def get_pihole_stats():
    try:
        r = requests.get(PIHOLE_API, timeout=2)
        if r.status_code == 200:
            return r.json()
    except Exception:
        return None
    return None


def render_page(wan_iface, lan_ifaces, captive_status):
    if wan_iface == "none":
        return [
            "Access Point Mode",
            "Config: 192.168.1.1",
            f"PIN: {CONFIG_PIN}",
            f"Clients: {get_client_count()}",
        ]

    wan_ip = get_ip_address(wan_iface)
    wan_line = f"WAN: {wan_iface} (CAPTIVE)" if captive_status == "CAPTIVE" else f"WAN: {wan_ip}"

    if page_index == 0:
        return [
            wan_line,
            f"WAN Port: {wan_iface}",
            f"LAN: {lan_ifaces}",
            f"Clients: {get_client_count()}",
        ]
    elif page_index == 1:
        return [
            "Atlantis Router",
            "Hold 5s → Copy logs",
            "Hold 10s → Shutdown",
            f"Clients: {get_client_count()}",
        ]
    elif page_index == 2:
        summary = load_last_summary()
        if summary:
            return [
                "Last Session:",
                f"Clients~{int(summary.get('avg_clients',0))}",
                f"Ads~{int(summary.get('avg_ads_blocked',0))}",
                f"Qries~{int(summary.get('avg_queries',0))}",
                f"Blk%~{round(summary.get('avg_ads_pct',0),1)}%",
            ]
        else:
            return ["Last Session:", "No summary found"]
    elif page_index == 3:
        stats = get_pihole_stats()
        if stats:
            return [
                "Pi-hole Live:",
                f"Queries~{stats.get('dns_queries_today',0)}",
                f"Ads~{stats.get('ads_blocked_today',0)}",
                f"Blk%~{stats.get('ads_percentage_today',0)}%",
                f"Clients~{stats.get('unique_clients',0)}",
            ]
        else:
            return ["Pi-hole Live:", "No stats"]


def main():
    while True:
        check_button()

        wan_iface = read_file("/tmp/atlantis-wan", "none")
        lan_ifaces = read_file("/tmp/atlantis-lan", "")
        captive_status = read_file("/tmp/atlantis-status", "OK")

        lines = render_page(wan_iface, lan_ifaces, captive_status)
        draw_lines(lines)
        time.sleep(REFRESH_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        GPIO.cleanup()
