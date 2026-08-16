---
slug: dockge
title: Dockge
tags: [docker]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/dockge.webp
by: MickLesk
co_author: [tteck]
repo: https://github.com/louislam/dockge
site: https://github.com/louislam/dockge
port: 5001
maintainer: MickLesk
---

Dockge is a fancy, easy-to-use and reactive self-hosted docker compose.yaml stack-oriented manager. It provides a web UI for creating, editing, starting, and stopping Docker Compose stacks, with an interactive compose editor, container log viewer, and web terminal.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Requires nesting enabled on the container (Proxmox host: `pct set <CTID> --features nesting=1`)
- Installs Docker (docker-ce + compose plugin from the official Docker repo) automatically if missing
- Web UI on port 5001; stacks live in `/opt/stacks` (NOT removed on uninstall)
- Update with: `update-dockge` — Uninstall with: `uninstall-dockge`
- Re-running the installer offers update/uninstall via the framework guard
- Also available as a dedicated LXC: `scripts/lxc/dockge.sh`

## Links

- [Website](https://dockge.kuma.pet/)
- [GitHub](https://github.com/louislam/dockge)
