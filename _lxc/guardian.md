---
slug: guardian
title: Guardian
tags: [media, monitoring]
logo: /assets/logos/guardian.webp
by: HydroshieldMKII
repo: https://github.com/HydroshieldMKII/Guardian
site: https://github.com/HydroshieldMKII/Guardian
port: 3000
cpu: 2
ram: 2048
disk: 6
maintainer: HydroshieldMKII
---

Plex media server monitoring and management tool. Track viewer activity, manage access, and monitor server performance.

## Notes

- Access the web UI at `http://<ip>:3000` to complete setup.
- The frontend and backend run as separate systemd services (`guardian-backend`, `guardian-frontend`).
- Database is stored at `/opt/guardian/backend/plex-guard.db`.
- Configuration is stored in `/opt/guardian/.env`.

## Links

- [GitHub](https://github.com/HydroshieldMKII/Guardian)
