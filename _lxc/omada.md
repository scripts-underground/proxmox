---
slug: omada
title: Omada
tags: [tp-link, controller]
logo: /assets/logos/omada.webp
by: tteck
repo: https://github.com/community-scripts/ProxmoxVE
site: https://www.tp-link.com/us/support/download/omada-software-controller/
port: 8043
cpu: 2
ram: 3072
disk: 8
maintainer: tteck
---

Omada Software Controller is a web-based management platform by TP-Link for centralized administration of Omada access points, switches, and gateways. It provides unified network monitoring, batch configuration, and firmware upgrades.

## Notes

- Access the web UI at `https://<ip>:8043` to complete the initial setup.
- Requires MongoDB 8.0 and Java 21 — installed automatically.
- The controller installation is detected via `/opt/tplink`.
- Updates check tp-link.com for new `.deb` releases.
- AVX CPU support is required for non-ARM64 installations.

## Links

- [Website](https://www.tp-link.com/us/support/download/omada-software-controller/)
- [Omada Cloud](https://omada.tplinkcloud.com/)
