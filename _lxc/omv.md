---
slug: omv
title: OpenMediaVault
tags: [media]
logo: /assets/logos/omv.webp
by: tteck
repo: https://github.com/openmediavault/openmediavault
site: https://www.openmediavault.org/
port: 80
cpu: 2
ram: 1024
disk: 4
maintainer: tteck
---

Network-attached storage (NAS) solution based on Debian. Provides a web-based interface for managing storage, shares, users, and services.

## Notes

- Access the web UI at `http://{ip}` (port 80) with default credentials `admin` / `openmediavault`.
- Initial setup may take several minutes as it installs the full LAMP stack and OMV packages.
- OMV manages its own services — do not manually configure nginx, php, or other system services.

## Links

- [OpenMediaVault on GitHub](https://github.com/openmediavault/openmediavault)
- [Website](https://www.openmediavault.org/)
