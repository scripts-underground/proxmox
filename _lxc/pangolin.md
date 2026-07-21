---
slug: pangolin
title: Pangolin
tags: [proxy]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons/webp/pangolin.webp
by: tremor021
repo: https://github.com/fosrl/pangolin
site: https://pangolin.net/
port: 3002
cpu: 2
ram: 4096
disk: 10
maintainer: tremor021
---
Pangolin is a self-hosted tunneled reverse proxy with identity and access management, designed to securely expose private resources through encrypted WireGuard tunnels.
## Notes
- Uses PostgreSQL 17 as the database backend.
- Requires 4GB RAM for the initial build. After installation, you can reduce to 1GB or even 512MB.
- Type `journalctl -u pangolin | grep -oP 'Token:\s*\K\w+'` to get the admin token.
- Edit `/opt/pangolin/config/config.yml` to match your needs.
## Links
- [GitHub](https://github.com/fosrl/pangolin)
