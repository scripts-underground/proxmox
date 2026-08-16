---
slug: immich-public-proxy
title: Immich Public Proxy
tags: [photos, proxy]
logo: /assets/logos/immich-public-proxy.webp
by: vhsdream
repo: https://github.com/alangrainger/immich-public-proxy
site: https://github.com/alangrainger/immich-public-proxy
port: 3000
maintainer: vhsdream
---

Immich Public Proxy is a lightweight companion proxy for Immich that safely exposes only your publicly-shared photos and albums. Share galleries with anyone without exposing your entire Immich instance to the internet.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Requires Node.js 24 (auto-installed if missing)
- During install you are asked for the IP/hostname of your LOCAL Immich instance
- Additional configuration is available at `/opt/immich-proxy/app/config.json`
- Update with: `update-immich-public-proxy` — Uninstall with: `uninstall-immich-public-proxy`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/alangrainger/immich-public-proxy)
