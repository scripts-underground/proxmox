---
slug: netboot-xyz
title: netboot.xyz
tags: [network, pxe, boot]
logo: /assets/logos/netboot-xyz.webp
by: MickLesk
repo: https://github.com/netbootxyz/netboot.xyz
site: https://netboot.xyz/
port: 80
cpu: 1
ram: 512
disk: 8
maintainer: MickLesk
---
Network boot utility using iPXE. Boot any OS or utility over the network without physical media.
## Notes
- HTTP on port 80 and TFTP on port 69/UDP, both serving from `/var/www/html`.
- Configure your DHCP server: set `next-server` to the container IP, `boot-filename` to `netboot.xyz.efi` (UEFI) or `netboot.xyz.kpxe` (BIOS/legacy).
- Customize menus by editing `/var/www/html/boot.cfg`. Changes are picked up immediately.
## Links
- [Website](https://netboot.xyz/)
- [Documentation](https://netboot.xyz/docs/)
