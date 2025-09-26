#!/usr/bin/env python3
import os
import time
import subprocess
import threading
from flask import Flask, render_template_string, request, redirect
from luma.core.interface.serial import i2c
from luma.oled.device import sh1106
from luma.core.render import canvas
from PIL import ImageFont
import RPi.GPIO as GPIO

# ==== OLED Setup ====
serial = i2c(port=1, address=0x3C)
device = sh1106(serial)
font = ImageFont.load_default()

# ==== Button Setup ====
BUTTON_PIN = 4
GPIO.setmode(GPIO.BCM)
GPIO.setup(BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

# Screen states
screens = ["wan", "ip", "clients"]
screen_index = 0

# ==== Flask Setup ====
app = Flask(__name__)

# HTML Template (Bootstrap)
PAGE_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
  <title>Travel Router Setup</title>
  <style>
    body { font-family: Arial; padding: 20px; }
    h1 { color: #333; }
    label { display:block; margin-top:10px; }
    input[type=text], input[type=password] { width: 300px; padding: 6px; }
    button { margin-top: 10px; padding: 8px 12px; }
  </style>
</head>
<body>
  <h1>Hotel Wi-Fi Setup</h1>
  <form method="POST" action="/connect">
    <label>Available Networks:</label>
    <select name="ssid">
      {% for s in ssids %}
        <option value="{{s}}">{{s}}</option>
      {% endfor %}
    </select>
    <label><input type="checkbox" name="openwifi" value="1"> Open network (no password)</label>
    <label>Password:</label>
    <input type="password" name="password">
    <br>
    <button type="submit">Connect</button>
  </form>
</body>
</html>
"""

def scan_wifi():
    """Return list of SSIDs from wlan1"""
    try:
        out = subprocess.check_output(
            ["nmcli", "-t", "-f", "SSID", "dev", "wifi", "list", "ifname", "wlan1"],
            stderr=subprocess.DEVNULL
        ).decode().splitlines()
        return sorted(set([s for s in out if s]))
    except Exception:
        return []

@app.route("/")
def index():
    return render_template_string(PAGE_TEMPLATE, ssids=scan_wifi())

@app.route("/connect", methods=["POST"])
def connect():
    ssid = request.form.get("ssid")
    password = request.form.get("password")
    openwifi = request.form.get("openwifi")

    if openwifi == "1":
        cmd = ["nmcli", "dev", "wifi", "connect", ssid, "ifname", "wlan1"]
    else:
        cmd = ["nmcli", "dev", "wifi", "connect", ssid, "password", password, "ifname", "wlan1"]

    try:
        subprocess.run(cmd, check=True)
        return redirect("/")
    except subprocess.CalledProcessError:
        return "Failed to connect", 500

# ==== OLED Update Thread ====
def get_wan_iface():
    try:
        out = subprocess.check_output(["ip", "route", "get", "8.8.8.8"]).decode()
        if "wlan1" in out:
            return "Wi-Fi"
        elif "eth0" in out:
            return "Ethernet"
        return "None"
    except:
        return "None"

def get_wifi_ssid():
    try:
        return subprocess.check_output(["iwgetid", "-r"]).decode().strip()
    except:
        return "Not connected"

def get_wan_ip():
    try:
        out = subprocess.check_output(["hostname", "-I"]).decode().split()
        return out[0] if out else "No IP"
    except:
        return "No IP"

def get_client_count():
    try:
        out = subprocess.check_output(["iw", "dev", "wlan0", "station", "dump"]).decode()
        return str(out.count("Station"))
    except:
        return "0"

def draw_screen():
    global screen_index
    while True:
        with canvas(device) as draw:
            if screens[screen_index] == "wan":
                draw.text((0, 0), "WAN: " + get_wan_iface(), font=font, fill=255)
                draw.text((0, 16), "SSID: " + get_wifi_ssid(), font=font, fill=255)
            elif screens[screen_index] == "ip":
                draw.text((0, 0), "WAN IP:", font=font, fill=255)
                draw.text((0, 16), get_wan_ip(), font=font, fill=255)
            elif screens[screen_index] == "clients":
                draw.text((0, 0), "Clients:", font=font, fill=255)
                draw.text((0, 16), get_client_count(), font=font, fill=255)
        time.sleep(2)

def button_monitor():
    global screen_index
    while True:
        if GPIO.input(BUTTON_PIN) == GPIO.LOW:
            screen_index = (screen_index + 1) % len(screens)
            time.sleep(0.3)  # debounce
        time.sleep(0.1)

# ==== Main Entrypoint ====
if __name__ == "__main__":
    threading.Thread(target=draw_screen, daemon=True).start()
    threading.Thread(target=button_monitor, daemon=True).start()
    app.run(host="0.0.0.0", port=80)
