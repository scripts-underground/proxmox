---
slug: excalidash
title: ExcaliDash
tags: [documents, drawing, collaboration]
logo: /assets/logos/excalidash.webp
by: MickLesk
repo: https://github.com/ZimengXiong/ExcaliDash
site: https://github.com/ZimengXiong/ExcaliDash
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

ExcaliDash is a collaborative whiteboard and drawing application built on Excalidraw with real-time collaboration features.

## Notes

- Access the web UI at `http://<ip>` (port 80).
- Uses PostgreSQL for storage (new installs); existing SQLite installs keep working through updates.
- The backend only accepts API mutations from origins listed in `FRONTEND_URL` (exact match on the browser's `Origin` header). The installer seeds it automatically with the container's IP, short hostname, and FQDN — browsing via any of those just works.
- To use additional names (custom domain, reverse proxy), append them comma-separated to `FRONTEND_URL` in `/opt/excalidash_data/.env` and run `systemctl restart excalidash`. Without this, actions like toggling auth fail with "Origin not allowed".

## Links

- [GitHub](https://github.com/ZimengXiong/ExcaliDash)
