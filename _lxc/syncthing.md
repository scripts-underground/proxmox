---
slug: syncthing
title: Syncthing
tags: [sync]
logo: /assets/logos/syncthing.webp
by: tteck
repo: https://github.com/syncthing/syncthing
site: https://syncthing.net/
port: 8384
cpu: 2
ram: 2048
disk: 8
maintainer: tteck
---

Continuous file synchronization program. Synchronizes files between two or more computers in real time, safely protected from prying eyes.

## Notes

- Access the web UI at `http://<ip>:8384` to complete setup.
- Installed via the official Syncthing apt repository.
- The config file at `~/.local/state/syncthing/config.xml` is patched to bind to `0.0.0.0`.
- Updates are handled via `apt upgrade`.

## Links

- [Website](https://syncthing.net/)
- [GitHub](https://github.com/syncthing/syncthing)
