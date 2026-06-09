---
slug: opnsense-vm
title: OPNsense
tags: [firewall, network, router]
logo: /assets/logos/opnsense-vm.webp
by: michelroegl-brunner
repo: https://opnsense.org
site: https://opnsense.org
cpu: 4
ram: 8192
disk: 10
port: 443
maintainer: michelroegl-brunner
---

Creates an OPNsense firewall/router virtual machine on Proxmox VE with dual NIC support.

## Notes

- Requires a WAN bridge (default: vmbr1) and LAN bridge (default: vmbr0)
- Installation takes 20-30 minutes (bootstraps OPNsense from FreeBSD)
- Supports static IP or DHCP for both WAN and LAN interfaces
- Default credentials: `root` / `opnsense`

## Links

- [Website](https://opnsense.org)
