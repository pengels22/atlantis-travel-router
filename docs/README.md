# Atlantis Travel Router

Atlantis is a Raspberry Pi–based travel router project that provides:
- Dual-Ethernet + Wi-Fi flexibility
- Auto WAN detection (hotel Ethernet or Wi-Fi)
- Atlantis LAN (Wi-Fi AP + LAN ports)
- Pi-hole ad blocking
- Tailscale exit node support (tunnel all LAN traffic home)
- Captive portal for setup when offline
- OLED display with live network status

## Features
- **Auto WAN/LAN switching**
  - Plug hotel Ethernet into either port → it becomes WAN
  - Otherwise, hotel Wi-Fi becomes WAN
- **Atlantis LAN** always on:
  - `wlan0` = Atlantis Wi-Fi AP
  - `192.168.1.0/24` subnet
  - Gateway: `192.168.1.1`
- **Ad Blocking** → Pi-hole included
- **Secure Remote Access** → Tailscale exit node
- **OLED Display**
  - WAN IP
  - WAN port
  - LAN ports
  - Client count
  - Fallback: Access Point Mode + Config PIN
- **Captive Portal**
  - When no WAN is detected
  - Access config page at `http://192.168.1.1`
  - PIN-protected (default: `0831`)

## Hardware
- Raspberry Pi 4B (4GB)
- USB Wi-Fi adapter (for hotel upstream)
- USB Ethernet adapter (for second LAN/WAN port)
- SH1106 OLED display (I²C)
- Button (optional, for page navigation)
- Pelican case + passthroughs
