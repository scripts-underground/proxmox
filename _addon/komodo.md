---
slug: komodo
title: Komodo
tags: [docker]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/komodo.webp
by: MickLesk
repo: https://github.com/moghtech/komodo
site: https://komo.do
port: 9120
maintainer: MickLesk
---

Komodo is a tool to build and deploy software on many servers, providing a web UI for managing Docker containers, infrastructure, and deployments.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Installs Docker if missing; the LXC must have **nesting enabled** (`pct set <ctid> --features nesting=1`) for Docker to run
- Deploys the official Komodo compose stack to `/opt/komodo` with your choice of MongoDB (recommended) or FerretDB
- Web UI on port 9120; login `admin` with the generated password, saved to `~/komodo.creds` inside the container
- Update with: `update-komodo` — Uninstall with: `uninstall-komodo`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://komo.do)
- [GitHub](https://github.com/moghtech/komodo)
