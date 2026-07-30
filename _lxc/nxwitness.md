---
slug: nxwitness
title: NxWitness
tags: [nvr-cameras]
logo: /assets/logos/nxwitness.webp
by: MickLesk
repo: https://nxvms.com/download/releases/linux
site: https://www.networkoptix.com/nx-witness
port: 7001
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

NxWitness (formerly Nx Witness) is a professional video management system (VMS) designed for IP cameras and surveillance systems. It provides real-time video streaming, recording, and remote access with an intuitive user interface. The software supports AI-based video analytics, integrates with third-party security systems, and offers advanced search and event management features.

## Notes

- Access the web UI at `http://{ip}:7001` to complete the initial setup.
- GPU hardware acceleration is enabled by default for supported devices.
- The container uses Ubuntu 24.04 and requires a privileged container with GPU passthrough.
- Updates are fetched from the official Network Optix update server on each script run.

## Links

- [Website](https://www.networkoptix.com/nx-witness)
- [Downloads](https://nxvms.com/download/releases/linux)
- [Documentation](https://support.networkoptix.com/hc/en-us/articles/360006863413-Access-the-Nx-Witness-User-Manual)
