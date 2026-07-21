---
slug: snapotter
title: SnapOtter
tags: [media, image]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/snapotter.webp
by: CanbiZ
co_author: []
repo: https://github.com/snapotter-hq/SnapOtter
site: https://snapotter.com
port: 1349
cpu: 2
ram: 4096
disk: 20
maintainer: CanbiZ
---

SnapOtter is a self-hosted media processing and image manipulation platform.

## Notes

- Access the web UI at `http://<ip>:1349` to complete setup.
- Default credentials: `admin` / `admin`.
- Requires PostgreSQL 17 and Redis for full functionality.
- The service uses pnpm workspaces — the API runs via `@snapotter/api`.

## Links

- [GitHub](https://github.com/snapotter-hq/SnapOtter)
- [Website](https://snapotter.com)
