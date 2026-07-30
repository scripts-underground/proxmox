---
slug: dispatcharr
title: Dispatcharr
tags: [media, arr]
logo: /assets/logos/dispatcharr.webp
by: ekke85
co_author: [MickLesk]
repo: https://github.com/Dispatcharr/Dispatcharr
site: https://github.com/Dispatcharr/Dispatcharr
port: 9191
cpu: 2
ram: 2048
disk: 8
maintainer: ekke85
---

Dispatcharr is an open-source powerhouse for managing IPTV streams and EPG data with elegance and control. Think of it as the *arr family's IPTV cousin — manages M3U accounts, EPG sources, transcoding profiles, and multi-provider failover.

## Notes

- Access the web UI at `http://<ip>:9191` to configure providers and channels.
- Uses PostgreSQL for data storage and Redis for Celery task queue.
- Supports hardware acceleration for transcoding when available.
- Config files and data stored at `/opt/dispatcharr/.env` and `/data/`.

## Links

- [GitHub](https://github.com/Dispatcharr/Dispatcharr)
- [Docs](https://dispatcharr.github.io/Dispatcharr-Docs/)
