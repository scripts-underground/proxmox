---
slug: scanopy
title: Scanopy
tags: [analytics]
logo: /assets/logos/scanopy.webp
by: vhsdream
repo: https://github.com/scanopy/scanopy
site: https://github.com/scanopy/scanopy
port: 60072
cpu: 4
ram: 4096
disk: 8
maintainer: vhsdream
---

Network discovery and analytics platform. Scanopy helps you map, monitor, and analyze network devices and services.

## Notes

- Access the web UI at `http://{ip}:60072` to set up your account.
- After account creation, generate a daemon API key in the UI and configure a daemon for network discovery.
- Uses PostgreSQL for data storage and Rust for high-performance backend processing.
- The integrated daemon runs on port 60073 (internal).

## Links

- [GitHub](https://github.com/scanopy/scanopy)
- [Configuration Guide](https://github.com/scanopy/scanopy/blob/main/docs/CONFIGURATION.md)
