---
slug: cloudflare-ddns
title: Cloudflare-DDNS
tags: [network]
logo: /assets/logos/cloudflare-ddns.webp
by: edoardop13
co_author: [favonia]
repo: https://github.com/favonia/cloudflare-ddns
site: https://github.com/favonia/cloudflare-ddns
port: 0
cpu: 2
ram: 1024
disk: 3
maintainer: edoardop13
---

A feature-rich and robust Cloudflare DDNS updater with a small Docker image. It detects your machine's public IP addresses and updates DNS records through the Cloudflare API.

## Notes

- A Cloudflare API token with **Zone - DNS - Edit** permission is required.
- The updater runs as a systemd service, checking for IP changes every 5 minutes.
- IPv4 is enabled by default; IPv6 can be enabled during setup.

## Links

- [GitHub](https://github.com/favonia/cloudflare-ddns)
