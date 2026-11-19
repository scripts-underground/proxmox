---
slug: bambuddy
title: Bambuddy
tags: [media, 3d-printing]
logo: /assets/logos/bambuddy.webp
by: Adrian-RDA
repo: https://github.com/maziggy/bambuddy
site: https://github.com/maziggy/bambuddy
port: 8000
cpu: 2
ram: 2048
disk: 10
maintainer: Adrian-RDA
---

Bambu Lab 3D printer management — monitor prints, manage files, and control Bambu Lab printers from a web interface.

## Notes

- Access the web UI at `http://<ip>:8000` to manage your Bambu Lab printers.
- Configuration is stored in `/opt/bambuddy/.env`.
- The default database is `/opt/bambuddy/bambuddy.db`; archives are in `/opt/bambuddy/archive/`, and authentication keys are in `/opt/bambuddy/data/`. Updates retain these and the other application data directories.

## Links

- [GitHub](https://github.com/maziggy/bambuddy)
