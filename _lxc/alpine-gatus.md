---
slug: alpine-gatus
title: Gatus on Alpine
tags: [alpine, monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/gatus.webp
by: tremor021
repo: https://github.com/TwiN/gatus
site: https://github.com/TwiN/gatus
port: 8080
cpu: 1
ram: 512
disk: 3
maintainer: tremor021
---

Gatus is a health monitoring dashboard that monitors your services via HTTP, ICMP, TCP, and DNS.

## Notes

- Access the web UI at `http://<ip>:8080` to view the dashboard.
- Configuration is stored in `/opt/gatus/config/config.yaml`.
- Gatus is built from source on initial install and on each update — updates may take a few minutes.

## Links

- [GitHub](https://github.com/TwiN/gatus)
