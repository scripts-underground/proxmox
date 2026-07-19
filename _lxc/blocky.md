---
slug: blocky
title: Blocky
tags: [adblock]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/blocky.webp
by: tteck
repo: https://github.com/0xERR0R/blocky
site: https://0xerr0r.github.io/blocky
port: 0
cpu: 1
ram: 512
disk: 2
maintainer: tteck
---
DNS proxy and ad-blocker. Provides network-wide ad blocking with DNS-over-TLS and custom filtering.
## Notes
- DNS service runs on port 53.
- Configure upstream DNS and denylists in `/opt/blocky/config.yml`.
- Disables systemd-resolved automatically.
## Links
- [Website](https://0xerr0r.github.io/blocky)
