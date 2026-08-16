---
slug: jellystat
title: Jellystat
tags: [monitoring-analytics]
logo: /assets/logos/jellystat.webp
by: MickLesk
repo: https://github.com/CyferShepard/Jellystat
site: https://github.com/CyferShepard/Jellystat
port: 3000
maintainer: MickLesk
---

A free and open source statistics app for Jellyfin

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Requires Node.js 22 and PostgreSQL 17 (auto-installed if missing)
- Generated database credentials and JWT secret are saved to `/root/jellystat.creds`
- Update with: `update-jellystat` — Uninstall with: `uninstall-jellystat`

## Links

- [GitHub](https://github.com/CyferShepard/Jellystat)
