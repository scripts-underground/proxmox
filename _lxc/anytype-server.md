---
slug: anytype-server
title: Anytype-Server
tags: [notes, productivity, sync]
logo: /assets/logos/anytype-server.webp
by: MickLesk
repo: https://github.com/grishy/any-sync-bundle
site: https://anytype.io
port: 33010
cpu: 2
ram: 4096
disk: 16
maintainer: MickLesk
---
Anytype self-hosted sync server. Encrypted collaboration and sync for the Anytype knowledge base app.
## Notes
- Import `/opt/anytype/data/client-config.yml` from the container into the Anytype client.
- Sync uses DRPC on TCP port 33010 and QUIC on UDP port 33020; there is no web UI.
- Based on Ubuntu 24.04 with MongoDB replica set and Redis Stack.
- Requires the Anytype desktop/mobile client to connect.
## Links
- [Website](https://anytype.io)
