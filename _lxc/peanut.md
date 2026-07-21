---
slug: peanut
title: PeaNUT
tags: [network, ups]
logo: /assets/logos/peanut.webp
by: tteck
co_author: [remz1337]
repo: https://github.com/Brandawg93/PeaNUT
site: https://github.com/Brandawg93/PeaNUT
port: 8080
cpu: 2
ram: 4096
disk: 7
maintainer: tteck
---

PeaNUT is a modern web interface for NUT (Network UPS Tools), allowing you to monitor and manage UPS devices connected to your network.

## Notes

- PeaNUT requires a working NUT server on the network. The client package (`nut-client`) is installed automatically for CLI tools, but you must configure `/etc/peanut/settings.yml` to point to your NUT server.
- The default port is **8080**.
- During the first start, you can set `WEB_USERNAME` and `WEB_PASSWORD` in `/etc/peanut/peanut.env` to bootstrap an admin account (only applied on first launch).

## Links

- [GitHub](https://github.com/Brandawg93/PeaNUT)
- [Documentation](https://github.com/Brandawg93/PeaNUT)
