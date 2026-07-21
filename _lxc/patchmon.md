---
slug: patchmon
title: PatchMon
tags: [monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/patchmon.webp
by: vhsdream
repo: https://github.com/PatchMon/PatchMon
site: https://patchmon.net/
port: 3000
cpu: 2
ram: 2048
disk: 4
maintainer: vhsdream
---

Enterprise-grade Linux patch and server management platform with real-time visibility, security update tracking, and comprehensive package management across your entire fleet. Features outbound-only agents requiring no inbound firewall changes.

## Notes

- Uses PostgreSQL 17 for data storage and Redis for background job queues.
- Server binary is a single Go binary with embedded React frontend.
- Agent binaries for multiple platforms are downloaded during installation.
- Credentials (REDIS_PASSWORD, JWT_SECRET, SESSION_SECRET, AI_ENCRYPTION_KEY) are stored in `/opt/patchmon/.env`.
- Access the web UI at `http://<ip>:3000` and complete the first-time admin setup.

## Links

- [Website](https://patchmon.net/)
- [GitHub](https://github.com/PatchMon/PatchMon)
- [Documentation](https://patchmon.net/docs/)
