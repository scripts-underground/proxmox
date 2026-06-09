---
slug: proxmox-ve-vm
title: Proxmox VE (Nested)
tags: [proxmox, virtualization, hypervisor]
logo: /assets/logos/proxmox-ve-vm.webp
by: alexindigo
repo: https://www.proxmox.com
site: https://www.proxmox.com
cpu: 4
ram: 4096
disk: 30
port: 8006
maintainer: alexindigo
---

Creates a Proxmox VE virtual machine inside your existing Proxmox host — nested virtualization for sandboxed PVE environments.

## Notes

- Requires CPU with virtualization support (host CPU mode)
- Cloud-Init used to bootstrap PVE packages on Debian 13
- PVE web interface will be available on port 8006 of the VM

## Links

- [Website](https://www.proxmox.com)
- [Download](https://www.proxmox.com/downloads)
