---
slug: seelf
title: seelf
tags: [server, docker]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/seelf.webp
by: tremor021
repo: https://github.com/YuukanOO/seelf
site: https://yuukanoo.github.io/seelf/
port: 8080
cpu: 2
ram: 4096
disk: 10
maintainer: tremor021
---

Painless self-hosted deployment platform. Send your Docker Compose files to seelf and they're live on your infrastructure.

## Notes

- Access the web UI at `http://<ip>:8080` to complete setup.
- Admin credentials are written to `~/seelf.creds` inside the container.
- The app is built from source using Go during installation; the first install may take several minutes.

## Links

- [GitHub](https://github.com/YuukanOO/seelf)
- [Website](https://yuukanoo.github.io/seelf/)
