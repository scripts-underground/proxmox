---
slug: wireguard
title: WireGuard
tags: [network, vpn]
logo: /assets/logos/wireguard.webp
by: tteck
repo: https://github.com/WGDashboard/WGDashboard
site: https://www.wireguard.com/
port: 51820
cpu: 1
ram: 512
disk: 4
maintainer: tteck
---

WireGuard is a fast, modern VPN tunnel designed with security and simplicity in mind. This container installs WireGuard and optionally WGDashboard for web-based management.

## Notes

- TUN device is required — enable it during container creation.
- Optionally installs WGDashboard (web UI) during setup.
- Access WGDashboard at `http://{ip}:10086` if installed.
- WireGuard listens on UDP port 51820 by default.

## Links

- [WireGuard Website](https://www.wireguard.com/)
- [WGDashboard on GitHub](https://github.com/WGDashboard/WGDashboard)
