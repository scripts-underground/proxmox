---
slug: runtipi
title: Runtipi
tags: [docker, hosting]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/runtipi.webp
by: MickLesk
repo: https://github.com/runtipi/runtipi
site: https://runtipi.io/
port: 80
maintainer: MickLesk
---

Runtipi is a self-hosted PaaS solution for deploying and managing applications with an intuitive web interface. It uses Docker under the hood to orchestrate app deployments. This addon installs Runtipi into an existing LXC container via the official runtipi.io installer, which sets up the Runtipi CLI and pulls its Docker containers.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Requires nesting enabled on the container (Proxmox host: `pct set <CTID> --features nesting=1`)
- Installs Docker automatically if missing; installs Runtipi to `/opt/runtipi`, managed via the bundled `runtipi-cli` (no separate systemd unit)
- Web UI on port 80 (HTTP) and 443 (HTTPS)
- The installer pulls an external script from https://runtipi.io/ which is not maintained or audited by our repository — a confirmation prompt gates it
- Update with: `update-runtipi` — Uninstall with: `uninstall-runtipi`
- Re-running the installer offers update/uninstall via the framework guard
- Also available as a dedicated LXC: `scripts/lxc/runtipi.sh`

## Links

- [Website](https://runtipi.io/)
- [GitHub](https://github.com/runtipi/runtipi)
