---
slug: bytestash
title: ByteStash
tags: [code]
logo: /assets/logos/bytestash.webp
by: tremor021
repo: https://github.com/jordan-dalby/ByteStash
site: https://github.com/jordan-dalby/ByteStash
port: 3000
cpu: 2
ram: 2048
disk: 4
maintainer: tremor021
---

A self-hosted web application to store, organise, and manage code snippets efficiently.

## Notes

- Access the web UI at `http://<ip>:3000`.
- The first account created is the admin account.
- Snippets and the persisted JWT secret are stored under `/opt/bytestash/data/snippets`.
- Updates preserve the current data directory and leave legacy `/opt/data` in place.

## Links

- [GitHub](https://github.com/jordan-dalby/ByteStash)
- [Releases](https://github.com/jordan-dalby/ByteStash/releases)
