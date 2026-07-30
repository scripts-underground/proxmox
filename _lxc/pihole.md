---
slug: pihole
title: Pi-hole
tags: [adblock]
logo: /assets/logos/pihole.webp
by: tteck
repo: https://github.com/pi-hole/pi-hole
site: https://pi-hole.net/
port: 80
cpu: 1
ram: 512
disk: 2
maintainer: tteck
---

Network-wide ad blocking via your own DNS server. Blocks ads and trackers across every device on your network.

## Notes

- Access the web admin interface at `http://{ip}/admin`
- The web interface password is stored in `/etc/pihole/setupVars.conf` on the container
- Point your router's DNS (or individual device DNS) at the container's IP to enable network-wide filtering
- To update, run the Update option from the Proxmox helper script interface

## Links

- [Pi-hole on GitHub](https://github.com/pi-hole/pi-hole)
- [Website](https://pi-hole.net/)
