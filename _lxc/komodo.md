---
slug: komodo
title: Komodo
tags: [docker]
logo: /assets/logos/komodo.webp
by: MickLesk
repo: https://github.com/moghtech/komodo
site: https://komo.do/
port: 9120
cpu: 2
ram: 2048
disk: 10
maintainer: MickLesk
---

Komodo is a tool to build and deploy software on many servers, providing a web UI for managing Docker containers, infrastructure, and deployments.

## Notes

- Access the web UI at `http://{ip}:9120` to log in.
- Default credentials: username `admin`, password saved to `~/komodo.creds` inside the container.
- Komodo runs via Docker Compose with MongoDB.

## Links

- [GitHub](https://github.com/moghtech/komodo)
- [Website](https://komo.do/)
