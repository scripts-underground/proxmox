---
slug: leafwiki
title: LeafWiki
tags: [wiki, markdown, notes]
logo: /assets/logos/leafwiki.webp
by: MickLesk
repo: https://github.com/perber/leafwiki
site: https://leafwiki.com
port: 8080
cpu: 1
ram: 512
disk: 4
maintainer: MickLesk
---

Self-hosted wiki. Single Go binary. SQLite + Markdown on disk. No external database required.

## Notes

- Access the wiki at `http://{ip}:8080`.
- Admin password is set in `/etc/leafwiki/.env`.
- No Node.js, Redis, or Postgres needed — just a binary and a data directory.

## Links

- [GitHub](https://github.com/perber/leafwiki)
- [Website](https://leafwiki.com)
