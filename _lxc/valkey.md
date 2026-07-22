---
slug: valkey
title: Valkey
tags: [database]
logo: /assets/logos/valkey.webp
by: lazarillo
repo: https://github.com/valkey-io/valkey
site: https://valkey.io/
port: 6379
cpu: 1
ram: 1024
disk: 4
maintainer: lazarillo
---

Valkey is a high-performance key-value data store offering compatibility with the Redis protocol.

## Notes

- Access the web UI at `http://<ip>:6379` to connect to the Valkey server.
- Credentials are stored in `~/valkey.creds` inside the container.
- Upgrade via `apt update && apt upgrade -y`.

## Links

- [GitHub](https://github.com/valkey-io/valkey)
- [Website](https://valkey.io/)
