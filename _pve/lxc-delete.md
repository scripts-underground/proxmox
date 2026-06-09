---
slug: lxc-delete
title: PVE LXC Deletion
tags: [proxmox]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/linuxcontainers.webp
by: MickLesk
maintainer: MickLesk
---

This script helps manage and delete LXC containers on a Proxmox VE server. It lists all available containers, allowing the user to select one or more for deletion through an interactive menu. Running containers are automatically stopped before deletion, and the user is asked to confirm each action.

## Notes

- Execute within the Proxmox shell
- Supports manual and automatic deletion modes
- Protected containers are skipped in automatic mode

## Links

- [GitHub](https://github.com/community-scripts/ProxmoxVED)
