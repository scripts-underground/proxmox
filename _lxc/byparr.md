---
slug: byparr
title: Byparr
tags: [proxy]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/byparr.webp
by: luismco
repo: https://github.com/ThePhaseless/Byparr
site: https://github.com/ThePhaseless/Byparr
port: 8191
cpu: 2
ram: 2048
disk: 4
maintainer: luismco
---

Drop-in FlareSolverr replacement using camoufox and FastAPI. Bypasses Cloudflare and anti-bot challenges for your \*arr stack (Prowlarr, Radarr, Sonarr, etc.).

## Notes

- Access the web UI at `http://<ip>:8191/docs` for the API documentation.
- Configure your \*arr apps to use `http://<ip>:8191/v1` as the FlareSolverr URL.
- Updates are handled via the script's update mechanism.

## Links

- [GitHub](https://github.com/ThePhaseless/Byparr)
