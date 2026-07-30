---
slug: teleport
title: Teleport
tags: [zero-trust]
logo: /assets/logos/teleport.webp
by: tremor021
repo: https://github.com/gravitational/teleport
site: https://goteleport.com/
port: 3080
cpu: 1
ram: 1024
disk: 4
maintainer: tremor021
---

Teleport is a secure access platform that provides identity-aware proxy, SSH access, and zero-trust security for infrastructure.

## Notes

- Access the web UI at `https://<ip>:3080` to log in.
- Admin credentials (invite link) are stored at `~/teleportadmin.txt` inside the container.
- Teleport updates are managed via the system package manager (`apt upgrade`).

## Links

- [GitHub](https://github.com/gravitational/teleport)
- [Website](https://goteleport.com/)
