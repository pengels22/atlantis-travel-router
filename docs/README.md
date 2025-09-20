# 🌊 Atlantis Travel Router

A Raspberry Pi–based travel router that creates a **secure private network** (“Atlantis”) while bridging hotel Wi-Fi or Ethernet. Includes **Pi-hole ad blocking**, **Tailscale VPN exit node support**, and an **OLED display** for real-time status.

---

## ✨ Features
- Dual-WAN auto detection:
  - **Wi-Fi uplink** (wlan1)
  - **Ethernet uplink** (eth0 / eth1, auto-detects which is WAN/LAN)
- LAN bridge on:
  - **Atlantis Wi-Fi (wlan0)**
  - **Ethernet LAN** (whichever is not WAN)
- OLED display:
  - WAN IP + port  
  - LAN ports in bridge  
  - Connected client count  
  - “Access Point Mode” if no WAN detected  
  - Shutdown + USB log copy with long button press  
- Captive portal detection + config splash page
- Pi-hole for DNS ad blocking
- Tailscale for secure home access (exit node support)
- Automatic logging (clients, upstream, speeds, Pi-hole stats)

---

## 📦 Hardware
- Raspberry Pi 4B (4GB recommended)
- USB Wi-Fi adapter (for upstream, wlan1)
- Two Ethernet ports (Pi native + USB adapter or HAT)
- SH1106 OLED display (I²C, 128×64)
- Push button for menu/shutdown
- Optional: USB drive (for log export)

---

## 🚀 Quick Install
Flash Raspberry Pi OS Lite → boot → SSH in → run:

```bash
wget https://raw.githubusercontent.com/pengels22/atlantis-travel-router/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

You will be prompted at the end to reboot. After reboot, the **Atlantis** SSID will be available.

---

## ⚙️ Services
These run under systemd:

- `wan-manager.service` → Detects WAN, builds LAN bridge, sets NAT
- `oled-status.service` → Updates OLED with status, handles shutdown button
- `portal.service` → Config splash page when no WAN is available
- `captive-watchdog.service` → Monitors WAN for captive portals
- `hostapd` → Provides Atlantis Wi-Fi
- `dnsmasq` → Provides DHCP/DNS for Atlantis network
- `pihole-FTL` → DNS blocking
- `tailscaled` → VPN connectivity

---

## 🔐 Default Config
- Atlantis SSID: `Atlantis`
- Password: `atlantis123`
- Subnet: `192.168.1.0/24`
- Gateway IP: `192.168.1.1`
- Config PIN (for splash portal): `0831`

You can change SSID, password, or channel by editing `/etc/hostapd/hostapd.conf`.

---

## 🖥️ OLED Button Functions
- **Short press** → Cycle OLED pages
- **Hold 5s** → Copy logs to USB (auto-detect mount path)
- **Hold 10s** → Save summary log + shutdown safely

---

## 📑 Logs
- Runtime logs reset on boot.
- Shutdown writes summary stats (WAN used, average speeds, client count, Pi-hole stats) to `/var/log/atlantis-summary-<date>.log`.
- USB export supported via button hold.

---

## 🧪 Development Mode
Skip Pi-hole and Tailscale installs:

```bash
sudo ./setup.sh --dev
```

---

## 🛠️ To-Do
- Add optional web UI for log viewing
- Add hotspot mode fallback if no upstream found
- Enhance bandwidth speed test integration

---

## 📜 License
MIT — free to use and modify.
