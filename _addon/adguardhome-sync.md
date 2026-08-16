---
slug: adguardhome-sync
title: AdGuardHome-Sync
tags: [adblock]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/adguardhome-sync.webp
by: MickLesk
repo: https://github.com/bakito/adguardhome-sync
site: https://github.com/bakito/adguardhome-sync
port: 8080
maintainer: MickLesk
---

AdGuardHome-Sync keeps one or more AdGuard Home replica instances in sync with a primary (origin) instance — filters, rewrites, DHCP leases, client settings, services and general configuration — on a cron schedule, with a small status web UI.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Prompts for origin and replica AdGuard Home instances during install
- Config: `/opt/adguardhome-sync/adguardhome-sync.yaml` — Web UI on port 8080
- Update with: `update-adguardhome-sync` — Uninstall with: `uninstall-adguardhome-sync`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/bakito/adguardhome-sync)
