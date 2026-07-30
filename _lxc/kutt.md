---
slug: kutt
title: Kutt
tags: [sharing]
logo: /assets/logos/kutt.webp
by: tomfrenzel
repo: https://github.com/thedevs-network/kutt
site: https://github.com/thedevs-network/kutt
port: 3000
cpu: 1
ram: 1024
disk: 2
maintainer: tomfrenzel
---

URL shortener built with Node.js. Supports custom domains, link management, visit analytics, and API access.

## Notes

- Access the web UI at `https://{ip}` if using internal SSL, or at your custom domain.
- During installation you can choose between internal (Caddy + self-signed) or external reverse proxy SSL.
- Update via the script's update function — backup/restore handles .env and sqlite data.

## Links

- [GitHub](https://github.com/thedevs-network/kutt)
