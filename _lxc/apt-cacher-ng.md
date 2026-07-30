---
slug: apt-cacher-ng
title: Apt-Cacher-NG
tags: [caching]
logo: ""
by: tteck
repo: https://wiki.debian.org/AptCacherNg
site: https://wiki.debian.org/AptCacherNg
port: 3142
cpu: 1
ram: 512
disk: 10
maintainer: tteck
---

Caching proxy for Debian/Ubuntu apt packages. Reduces bandwidth usage and speeds up package downloads for multiple machines.

## Notes

- Access the web report at `http://{ip}:3142/acng-report.html`.
- Configure clients to use this container as their apt proxy by pointing to `http://{ip}:3142`.
- The container automatically proxies its own apt traffic through localhost.

## Links

- [Debian Wiki](https://wiki.debian.org/AptCacherNg)
