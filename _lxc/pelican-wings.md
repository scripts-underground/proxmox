---
slug: pelican-wings
title: Pelican Wings
tags: [gaming]
logo: /assets/logos/pelican-wings.webp
by: bvdberg01
repo: https://github.com/pelican-dev/wings
site: https://pelican.dev/
port: 8080
cpu: 2
ram: 4096
disk: 8
maintainer: bvdberg01
---

Lightweight daemon that handles game and application server deployments, resource management, and communication with the Pelican Panel. Works alongside the Pelican Panel to manage servers at scale.

## Notes

- Port 8080 is the Wings daemon API, not a standalone panel web UI. Manage the node through your Pelican Panel.
- Docker is required and installed automatically.

## First configuration

Create a node in your Pelican Panel, then open that node's Configuration page. Copy its generated configuration into `/etc/pelican/config.yml` inside this LXC, or run the Panel's generated auto-deploy command inside the LXC to fetch it.

Wings cannot finish starting without a valid node configuration. After saving it, run `systemctl restart wings` inside the LXC, then check `systemctl status wings` and the node's connection in the Panel. For startup errors, inspect `journalctl -u wings`. The installer enables the service, but the daemon is not ready to manage servers until configuration is complete.

## Links

- [GitHub](https://github.com/pelican-dev/wings)
- [Website](https://pelican.dev/)
