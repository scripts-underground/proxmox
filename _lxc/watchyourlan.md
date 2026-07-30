---
slug: watchyourlan
title: WatchYourLAN
tags: [network]
logo: /assets/logos/watchyourlan.webp
by: tteckster
repo: https://github.com/aceberg/WatchYourLAN
site: https://github.com/aceberg/WatchYourLAN
port: 8840
cpu: 1
ram: 512
disk: 2
maintainer: tteckster
---

Lightweight network monitoring tool that scans and tracks devices on your local network using ARP requests.

## Notes

- Access the web UI at `http://<ip>:8840` to view your network devices.
- Configuration is stored in `/data/config.yaml`.
- Edit `/data/config.yaml` to change the network interface with the `iface` setting (default: eth0).
- The database is stored at `/data/db.sqlite`.

## Links

- [GitHub](https://github.com/aceberg/WatchYourLAN)
