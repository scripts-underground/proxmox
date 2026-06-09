---
slug: add-tailscale-lxc
title: Tailscale
tags: [vpn, network, tailscale]
logo: /assets/logos/add-tailscale-lxc.webp
by: tteck
repo: https://github.com/tailscale/tailscale
site: https://tailscale.com
maintainer: tteck
---

Install Tailscale inside an existing LXC container from the Proxmox VE host.

## Notes

- Run on the Proxmox VE host, not inside the container
- Select container from a list
- Reboot the container, then run `tailscale up` to activate

## Links

- [Website](https://tailscale.com)
- [GitHub](https://github.com/tailscale/tailscale)
