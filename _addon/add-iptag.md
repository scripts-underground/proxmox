---
slug: add-iptag
title: PVE LXC Tag
tags: [proxmox]
logo: /assets/logos/add-iptag.webp
by: MickLesk
repo: https://github.com/gitsang/iptag
maintainer: MickLesk
---

This script automatically adds IP address as tags to LXC containers or VM's using a systemd service. The service also updates the tags if a LXC/VM IP address is changed.

## Notes

- Execute within the Proxmox shell
- Configuration: `nano /opt/iptag/iptag.conf`. iptag Service must be restarted after change.
- The Proxmox Node must contain ipcalc and net-tools. `apt-get install -y ipcalc net-tools`
- You can execute the ip tool manually with `iptag-run`

## Links

- [GitHub](https://github.com/gitsang/iptag)
