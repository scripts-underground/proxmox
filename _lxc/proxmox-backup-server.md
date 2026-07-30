---
slug: proxmox-backup-server
title: Proxmox Backup Server
tags: [backup]
logo: /assets/logos/proxmox-backup-server.webp
by: tteck
repo: https://git.proxmox.com/?p=proxmox-backup.git;a=summary
site: https://www.proxmox.com/en/proxmox-backup-server
port: 8007
cpu: 2
ram: 2048
disk: 10
maintainer: tteck
---

Dedicated backup solution for Proxmox VE environments. Provides efficient, deduplicated backups for virtual machines and containers with client-side encryption and verification.

## Notes

- Access the web UI at `https://{ip}:8007` to complete setup.
- Installed via the official Proxmox apt repository (pbs-no-subscription) on x86_64, or via unofficial arm64 builds on ARM.
- Updates are handled via `apt upgrade`.
- Login using the `root` user with your Proxmox server password.

## Links

- [Website](https://www.proxmox.com/en/proxmox-backup-server)
- [Repository](https://git.proxmox.com/?p=proxmox-backup.git;a=summary)
