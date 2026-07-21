---
slug: proxmox-datacenter-manager
title: Proxmox Datacenter Manager
tags: [datacenter]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/proxmox.webp
by: CrazyWolf13
repo: https://git.proxmox.com/?p=proxmox-datacenter-manager.git;a=summary
site: https://www.proxmox.com/en/products/proxmox-datacenter-manager
port: 8443
cpu: 2
ram: 2048
disk: 10
maintainer: CrazyWolf13
---

Centralized management platform for Proxmox VE and Proxmox Backup Server nodes. Provides a unified dashboard for monitoring and managing multiple Proxmox installations from a single interface.

## Notes

- Access the web UI at `https://<ip>:8443` to complete setup.
- Installed via the official Proxmox apt repository (pdm-no-subscription).
- Updates are handled via `apt upgrade`.
- Login using the `root` user with your Proxmox server password.

## Links

- [Website](https://www.proxmox.com/en/products/proxmox-datacenter-manager)
- [Repository](https://git.proxmox.com/?p=proxmox-datacenter-manager.git;a=summary)
