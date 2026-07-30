---
slug: adguard
title: AdGuard Home
tags: [adblock]
logo: /assets/logos/adguard.webp
by: tteck
repo: https://github.com/AdguardTeam/AdGuardHome
site: https://adguard.com/
port: 3000
cpu: 1
ram: 512
disk: 2
maintainer: tteck
---

Network-wide software for blocking ads and tracking. Runs its own DNS server that blocks trackers and unwanted content across every device on your network.

## Notes

- Access the web UI at `http://<ip>:3000` to complete the initial setup wizard.
- Updates are handled from the AdGuard Home web UI, not via this script.
- Point your router's DNS (or individual device DNS) at the container's IP to enable network-wide filtering.

## Links

- [AdGuard Home on GitHub](https://github.com/AdguardTeam/AdGuardHome)
- [Website](https://adguard.com/)
