---
slug: webmin
title: Webmin
tags: [proxmox, system, web]
logo: /assets/logos/webmin.webp
by: tteck
repo: https://github.com/webmin/webmin
site: https://www.webmin.com/
port: 10000
maintainer: tteck
---

Webmin is a web-based system administration interface for Unix-like systems. It lets you manage users, packages, services, disks, cron jobs, network settings, and server configuration through a browser, with SSL enabled by default.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Web UI is HTTPS-only on port 10000 (self-signed certificate)
- Default login: `root` / `root` — change it immediately via Webmin Configuration
- Update with: `update-webmin` — Uninstall with: `uninstall-webmin`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://www.webmin.com/)
- [GitHub](https://github.com/webmin/webmin)
