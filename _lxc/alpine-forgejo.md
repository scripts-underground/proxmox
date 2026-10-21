---
slug: alpine-forgejo
title: Alpine-Forgejo
tags: [alpine, git]
logo: /assets/logos/alpine-forgejo.webp
by: An!ma
repo: https://codeberg.org/forgejo/forgejo
site: https://forgejo.org/
port: 80
cpu: 2
ram: 1024
disk: 8
maintainer: An!ma
---

Forgejo Git service on Alpine Linux. Self-hosted lightweight Git repository manager with issue tracking and CI/CD.

## Notes

- Access the web UI at `http://<ip>` on fresh installations. Updates retain existing configured ports.
- Based on Alpine Linux 3.23.
- Installed via Alpine package manager.
- Uses the distro's `forgejo` account and home/init configuration. Existing homes, SSH keys and data remain caller-owned.

## Links

- [Website](https://forgejo.org/)
- [Codeberg](https://codeberg.org/forgejo/forgejo)
