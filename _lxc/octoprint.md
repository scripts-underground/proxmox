---
slug: octoprint
title: OctoPrint
tags: [3d-printing]
logo: /assets/logos/octoprint.webp
by: tteck
repo: https://github.com/OctoPrint/OctoPrint
site: https://octoprint.org/
port: 5000
cpu: 1
ram: 1024
disk: 4
maintainer: tteck
---

Web interface and remote control for 3D printers. Monitor prints, manage files, and control your printer from anywhere.

## Notes

- Default setup wizard runs on first access — set up username, password, and printer connection.
- Requires privileged container (var_unprivileged=0) for serial port access and hardware integration.

## Links

- [Website](https://octoprint.org/)
- [GitHub](https://github.com/OctoPrint/OctoPrint)
- [Documentation](https://docs.octoprint.org/)
