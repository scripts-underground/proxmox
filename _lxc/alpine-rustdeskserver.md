---
slug: alpine-rustdeskserver
title: Alpine-RustDeskServer
tags: [alpine, monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/rustdesk.webp
by: tremor021
repo: https://github.com/lejianwen/rustdesk-server
site: https://rustdesk.com/
port: 21114
cpu: 1
ram: 512
disk: 3
maintainer: tremor021
---

RustDesk Server on Alpine Linux. Self-hosted remote desktop server with web management UI, using minimal system resources.

## Notes

- Access the web UI at `http://<ip>:21114`.
- Default credentials: `admin` / auto-generated password (shown on install).
- Credentials are saved to `~/rustdesk.creds` inside the container.
- Both RustDesk Server (hbbs/hbbr) and RustDesk API are installed and updated.

## Links

- [GitHub - rustdesk-server](https://github.com/lejianwen/rustdesk-server)
- [GitHub - rustdesk-api](https://github.com/lejianwen/rustdesk-api)
- [RustDesk](https://rustdesk.com/)
