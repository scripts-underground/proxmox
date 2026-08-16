---
slug: coolify
title: Coolify
tags: [docker, paas]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/coolify.webp
by: MickLesk
repo: https://github.com/coollabsio/coolify
site: https://coolify.io
port: 8000
maintainer: MickLesk
---

Coolify is a self-hostable PaaS (an open-source Heroku/Netlify/Vercel alternative) for deploying applications, databases, and services from Git repos or Docker images, managed through a web UI. The addon installs it into an existing LXC container via the official Coolify installer, which sets up Docker and deploys the Coolify stack.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) — this addon coexists with the full [Coolify LXC script](/scripts/lxc/coolify), which creates a dedicated container
- Installs Docker if missing; the LXC must have **nesting enabled** (`pct set <ctid> --features nesting=1`) for Docker to run
- Deploys to `/data/coolify` by running the official external installer from `cdn.coollabs.io` — not audited by this repository; review it before continuing
- Access the web UI at `http://<ip>:8000` to complete setup (create the admin account on first visit)
- Update with: `update-coolify` — Uninstall with: `uninstall-coolify` (uninstall stops and removes **all** Docker containers in the container, not just Coolify's)
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://coolify.io)
- [GitHub](https://github.com/coollabsio/coolify)
