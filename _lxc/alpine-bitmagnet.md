---
slug: alpine-bitmagnet
title: Alpine-bitmagnet
tags: [alpine, torrent]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/bitmagnet.webp
by: tremor021
repo: https://github.com/bitmagnet-io/bitmagnet
site: https://github.com/bitmagnet-io/bitmagnet
port: 3333
cpu: 2
ram: 2048
disk: 3
maintainer: tremor021
---

BitTorrent DHT crawler and content classification system on Alpine Linux. Discovers and indexes torrents across the BitTorrent DHT network.

## Notes

- Access the web UI at `http://<ip>:3333`.
- Based on Alpine Linux 3.23 with Go and PostgreSQL.
- You will be prompted for a TMDB API key during installation (optional).

## Links

- [GitHub](https://github.com/bitmagnet-io/bitmagnet)
