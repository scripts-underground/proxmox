---
slug: feishin
title: Feishin
tags: [music, player, streaming]
logo: /assets/logos/feishin.webp
by: MickLesk
co_author: [CanbiZ]
repo: https://github.com/jeffvli/feishin
site: https://github.com/jeffvli/feishin
port: 9180
cpu: 2
ram: 4096
disk: 8
maintainer: MickLesk
---

Modern self-hosted music player web client for Navidrome, Jellyfin, and OpenSubsonic-compatible servers.

Configure your music backend URL (`SERVER_URL`) in `/opt/feishin/.env`, then restart nginx.

## Notes

- Access the web UI at `http://{ip}:9180` to start playing
- Default backend is set to Jellyfin at `http://localhost:8096` — edit `/opt/feishin/.env` to change
- After changing `.env`, run `systemctl restart nginx` to apply

## Links

- [GitHub](https://github.com/jeffvli/feishin)
