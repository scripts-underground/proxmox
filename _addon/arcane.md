---
slug: arcane
title: Arcane
tags: [docker]
logo: /assets/logos/arcane.webp
by: summoningpixels
repo: https://github.com/getarcaneapp/arcane
site: https://getarcane.app
port: 3552
maintainer: summoningpixels
---

Arcane is a modern web UI for managing Docker environments — containers, images, volumes, networks, and Compose stacks — deployed inside the container via Docker Compose.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Installs Docker if missing; the LXC must have **nesting enabled** (`pct set <ctid> --features nesting=1`) for Docker to run
- Deploys the official `getarcaneapp/arcane` compose stack to `/opt/arcane`, with generated `ENCRYPTION_KEY`/`JWT_SECRET` secrets in `/opt/arcane/.env`
- Default login: `arcane` / `arcane-admin` — you'll be prompted to change the password on first access
- Update with: `update-arcane` — Uninstall with: `uninstall-arcane`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://getarcane.app)
- [GitHub](https://github.com/getarcaneapp/arcane)
