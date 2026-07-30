---
slug: frigate
title: Frigate
tags: [nvr]
logo: /assets/logos/frigate.webp
by: MickLesk
repo: https://github.com/blakeblackshear/frigate
site: https://frigate.video/
port: 5000
cpu: 8
ram: 4096
disk: 20
maintainer: MickLesk
---

Frigate is an open-source NVR built around AI object detection that processes real-time streams using local hardware acceleration.

## Notes

- Access the web UI at `http://{ip}:5000` to complete setup.
- This script requires Debian 12 (Bookworm) due to Python 3.11 build dependencies.
- To update Frigate, create a new container and transfer your configuration.

## Links

- [GitHub](https://github.com/blakeblackshear/frigate)
- [Website](https://frigate.video/)
