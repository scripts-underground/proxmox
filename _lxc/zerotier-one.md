---
slug: zerotier-one
title: Zerotier-One
tags: [networking]
logo: /assets/logos/zerotier-one.webp
by: tremor021
repo: https://github.com/zerotier/ZeroTierOne
site: https://www.zerotier.com/
port: 3443
cpu: 1
ram: 1024
disk: 4
maintainer: tremor021
---

ZeroTier is a smart programmable Ethernet switch for all of your devices. This LXC also includes ztncui, a web-based UI for managing ZeroTier networks.

## Notes

- Access the web UI at `https://<ip>:3443` to manage your ZeroTier network.
- Default login credentials for ztncui are `admin` / `password` (change on first login).
- ZeroTier client is installed directly from the official script at `install.zerotier.com`.
- On arm64, the ztncui UI is built from source (Node.js). On amd64, a prebuilt .deb is used.

## Links

- [GitHub](https://github.com/zerotier/ZeroTierOne)
- [Website](https://www.zerotier.com/)
