---
slug: portainer
title: Portainer
tags: [docker, proxmox]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/portainer.webp
by: MickLesk
repo: https://github.com/portainer/portainer
site: https://www.portainer.io
port: 9443
maintainer: MickLesk
---

Portainer CE is a lightweight web UI for managing Docker environments — containers, images, volumes, networks, stacks, and registries — deployed inside the container via Docker Compose.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Installs Docker if missing; the LXC must have **nesting enabled** (`pct set <ctid> --features nesting=1`) for Docker to run
- Deploys the official `portainer/portainer-ce:sts` compose stack to `/opt/portainer`, wrapped in a `portainer.service` systemd unit
- Web UI is HTTPS-only on port 9443 (self-signed certificate); port 8000 is exposed for Edge Agents
- On first access, you'll be prompted to create an admin account
- Update with: `update-portainer` — Uninstall with: `uninstall-portainer`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://www.portainer.io)
- [GitHub](https://github.com/portainer/portainer)
