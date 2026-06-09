---
slug: pve-privilege-converter
title: PVE Privilege Converter
tags: [proxmox]
logo: /assets/logos/pve-privilege-converter.webp
by: MickLesk
maintainer: MickLesk
---

This script allows converting Proxmox LXC containers between privileged and unprivileged modes using vzdump backup and restore. It guides you through container selection, backup storage, ID assignment, and privilege flipping via automated restore.

## Notes

- Execute this script inside the Proxmox shell as root.
- Ensure that the backup and target storage have enough space.
- The container will be recreated with a new ID and desired privilege setting.

## Links

- [GitHub](https://github.com/onethree7/proxmox-lxc-privilege-converter)
