---
slug: rustdeskserver
title: RustDesk Server
tags: [remote-desktop]
logo: /assets/logos/rustdeskserver.webp
by: tremor021
repo: https://github.com/lejianwen/rustdesk-server
site: https://rustdesk.com/
port: 21114
cpu: 1
ram: 512
disk: 2
maintainer: tremor021
---

RustDesk is a full-featured open source remote control alternative for self-hosting and security with minimal configuration.

## Notes

- Access the web UI at `http://<ip>:21114`.
- To set the admin password, run `cd /var/lib/rustdesk-api && rustdesk-api reset-admin-pwd <yournewpasswordhere>` inside the LXC.
- This install uses hbbs/hbbr builds from `lejianwen/rustdesk-server` for full compatibility with the RustDesk API (SSO/OAuth).

## Links

- [GitHub - rustdesk-server](https://github.com/lejianwen/rustdesk-server)
- [GitHub - rustdesk-api](https://github.com/lejianwen/rustdesk-api)
- [RustDesk](https://rustdesk.com/)
