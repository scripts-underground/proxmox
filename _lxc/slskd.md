---
slug: slskd
title: slskd
tags: [arr, p2p]
logo: /assets/logos/slskd.webp
by: vhsdream
repo: https://github.com/slskd/slskd
site: https://github.com/slskd/slskd/
port: 5030
cpu: 1
ram: 512
disk: 4
maintainer: vhsdream
---

Soulseek client daemon. Connects to the Soulseek peer-to-peer file sharing network. Optionally installs Soularr for Lidarr integration.

## Notes

- Access the web UI at `http://<ip>:5030`
- Default login: `slskd` / `slskd`
- Change the default password immediately via the web UI
- Soularr (optional) syncs wanted albums from Lidarr to slskd for automatic downloading
- Soularr runs every 10 minutes via a systemd timer

## Links

- [Website](https://github.com/slskd/slskd/)
- [GitHub](https://github.com/slskd/slskd)
- [Soularr](https://github.com/mrusse/soularr)
