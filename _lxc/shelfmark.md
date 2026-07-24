---
slug: shelfmark
title: Shelfmark
tags: [ebooks]
logo: /assets/logos/shelfmark.webp
by: vhsdream
repo: https://github.com/calibrain/shelfmark
site: https://github.com/calibrain/shelfmark
port: 8084
cpu: 2
ram: 2048
disk: 8
maintainer: vhsdream
---

Shelfmark is a self-hosted ebook management and automation platform that can search, download, and organize ebooks from various sources. Features include captcha bypassing via built-in Chromium or external FlareSolverr/Byparr, metadata enrichment, and a web-based interface.

## Notes

- Uses Python (uv) for the backend and Node.js for the frontend build.
- Configuration is stored in `/etc/shelfmark/.env`.
- Supports four deployment modes for captcha bypass: internal Chromium-based bypasser (default), FlareSolverr installed in the same LXC, external FlareSolverr/Byparr instance, or disabled bypassing.
- Access the web UI at `http://<ip>:8084`.

## Links

- [GitHub](https://github.com/calibrain/shelfmark)
