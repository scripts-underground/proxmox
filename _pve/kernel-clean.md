---
slug: kernel-clean
title: PVE Kernel Clean
tags: [proxmox, kernel, maintenance]
logo: /assets/logos/kernel-clean.webp
by: MickLesk
maintainer: MickLesk
---

Remove old Proxmox VE kernels to free up disk space, especially on small `/boot/efi` partitions.

## Notes

- Detects current kernel and lists removable kernels
- Select kernels to remove interactively
- Runs `update-grub` after cleanup

## Links

- [GitHub](https://github.com/community-scripts/ProxmoxVED)
