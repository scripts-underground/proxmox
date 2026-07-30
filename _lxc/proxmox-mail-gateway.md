---
slug: proxmox-mail-gateway
title: Proxmox Mail Gateway
tags: [mail]
logo: /assets/logos/proxmox-mail-gateway.webp
by: thost96
repo: https://git.proxmox.com/?p=pmg.git;a=summary
site: https://www.proxmox.com/en/products/proxmox-mail-gateway
port: 8006
cpu: 2
ram: 4096
disk: 10
maintainer: thost96
---

Enterprise-grade mail gateway with spam filtering, virus scanning, and policy-based email routing for Proxmox VE environments.

## Notes

- Access the web UI at `https://<ip>:8006` to complete setup.
- Installed via the official Proxmox apt repository (pmg-no-subscription).
- Updates are handled via `apt upgrade`.
- Login using the `root` user with your Proxmox server password.

## Links

- [Website](https://www.proxmox.com/en/products/proxmox-mail-gateway)
- [Repository](https://git.proxmox.com/?p=pmg.git;a=summary)
