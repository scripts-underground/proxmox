---
slug: dokploy
title: Dokploy
tags: [docker, paas]
logo: /assets/logos/dokploy.webp
by: MickLesk
repo: https://github.com/Dokploy/dokploy
site: https://dokploy.com
port: 3000
maintainer: MickLesk
---

Dokploy is a self-hostable PaaS (Platform as a Service) for deploying and managing applications, databases, and services with Docker. It provides a web dashboard with multi-server support, Docker Compose deployments, Traefik reverse proxy, and monitoring.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Requires nesting enabled on the LXC (`features: nesting=1`) for Docker; Docker Swarm may also need `keyctl=1`
- The upstream installer runs an external script from dokploy.com and requires ports 80, 443, and 3000 to be free
- Web UI is on port 3000; Traefik serves deployed apps on ports 80/443
- Update with: `update-dokploy` — Uninstall with: `uninstall-dokploy`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://dokploy.com/)
- [GitHub](https://github.com/Dokploy/dokploy)
