#!/usr/bin/env python3
# Atlantis Captive Portal
# Flask app to provide a config UI when no upstream WAN is detected.
# PIN protected (hardcoded: 0831)

from flask import Flask, request, render_template_string, redirect, url_for, session
import os

app = Flask(__name__)
app.secret_key = "atlantis_secret_key"  # Change if you want

CONFIG_PIN = "0831"

# === HTML Templates (inline for simplicity) ===
login_page = """
<!doctype html>
<title>Atlantis Portal - Login</title>
<h2>Atlantis Router</h2>
<form method="post">
  Enter PIN: <input type="password" name="pin">
  <input type="submit" value="Login">
</form>
"""

config_page = """
<!doctype html>
<title>Atlantis Portal - Config</title>
<h2>Atlantis Router Config</h2>
<p>Welcome! You are authenticated.</p>
<ul>
  <li><a href="{{ url_for('wifi') }}">Wi-Fi Setup</a></li>
  <li><a href="{{ url_for('tailscale') }}">Tailscale</a></li>
  <li><a href="{{ url_for('pihole') }}">Pi-hole</a></li>
</ul>
"""

wifi_page = """
<!doctype html>
<title>Atlantis Portal - Wi-Fi</title>
<h2>Wi-Fi Setup</h2>
<form method="post">
  SSID: <input type="text" name="ssid"><br>
  Password: <input type="password" name="password"><br>
  <input type="submit" value="Save">
</form>
"""

# === Routes ===
@app.route("/", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        pin = request.form.get("pin", "")
        if pin == CONFIG_PIN:
            session["auth"] = True
            return redirect(url_for("config"))
    return render_template_string(login_page)

@app.route("/config")
def config():
    if not session.get("auth"):
        return redirect(url_for("login"))
    return render_template_string(config_page)

@app.route("/wifi", methods=["GET", "POST"])
def wifi():
    if not session.get("auth"):
        return redirect(url_for("login"))
    if request.method == "POST":
        ssid = request.form.get("ssid", "")
        pw = request.form.get("password", "")
        with open("/etc/wpa_supplicant/wpa_supplicant.conf", "a") as f:
            f.write(f'\nnetwork={{\n    ssid="{ssid}"\n    psk="{pw}"\n}}\n')
        os.system("wpa_cli -i wlan1 reconfigure")
        return "<p>Wi-Fi credentials saved! Reconnecting...</p>"
    return render_template_string(wifi_page)

@app.route("/tailscale")
def tailscale():
    if not session.get("auth"):
        return redirect(url_for("login"))
    return "<p>Tailscale is installed. Run <code>sudo tailscale up</code> to configure.</p>"

@app.route("/pihole")
def pihole():
    if not session.get("auth"):
        return redirect(url_for("login"))
    return "<p>Pi-hole is active at <a href='http://192.168.1.1/admin'>192.168.1.1/admin</a></p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
