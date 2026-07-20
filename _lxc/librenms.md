---
slug: librenms
title: LibreNMS
tags: [monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/librenms.webp
by: michelroegl-brunner
repo: https://github.com/librenms/librenms
site: https://www.librenms.org/
port: 80
cpu: 2
ram: 2048
disk: 4
maintainer: michelroegl-brunner
---

Network monitoring platform with auto-discovery, alerting, and extensive device support.

## Notes

- Admin credentials saved to `~/librenms.creds` inside the container.
- Default admin user: `admin` with auto-generated password.
- SNMP community string is randomized during installation.
- Access the web UI at `http://<ip>`.

## Links

- [Website](https://www.librenms.org/)
- [GitHub](https://github.com/librenms/librenms)
