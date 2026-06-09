---
slug: post-pve-install
title: PVE Post Install
tags: [proxmox, system, configuration]
logo: /assets/logos/post-pve-install.webp
by: tteckster
maintainer: tteckster
---

Post-install configuration script for Proxmox VE.

Configures package repositories, disables subscription nag, manages enterprise/no-subscription repos, configures high availability, and performs system updates. Supports both Proxmox VE 8.x (Bookworm) and 9.x (Trixie) with proper deb822 sources format on 9.x.

## Features

- Configure Debian/Proxmox package sources
- Enable/disable enterprise, no-subscription, and test repositories
- Disable subscription nag message
- Configure high availability services
- System update and dist-upgrade

## Notes

- Run on each node individually in a cluster
- Reboot recommended after completion
- Clear browser cache after running (Ctrl+Shift+R)
