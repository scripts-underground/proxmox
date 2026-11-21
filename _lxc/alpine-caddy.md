---
slug: alpine-caddy
title: Alpine-Caddy
tags: [webserver]
logo: /assets/logos/alpine-caddy.webp
by: cobaltgit
repo: https://github.com/caddyserver/caddy
site: https://caddyserver.com/
port: 80
cpu: 1
ram: 256
disk: 3
maintainer: cobaltgit
---

Web server on Alpine Linux. Automatic HTTPS, reverse proxy, and static file serving with minimal resource usage.

## Notes

- Access the web server at `http://<ip>:80`.
- Based on Alpine Linux 3.23 with only 256 MB RAM.
- xCaddy addon installer available during initial setup.
- Optional xCaddy builds need at least 1024 MiB available RAM and 3584 MiB free on `/opt`; the package-only defaults are unchanged. Increase Memory and Root Disk in Proxmox Resources, then run `update` to retry a skipped build.
- xCaddy publishes its custom binary at `/opt/caddy`; the packaged Caddy service remains separate. Updates rebuild xCaddy only when it was installed or explicitly requested.

## Links

- [Website](https://caddyserver.com/)
- [GitHub](https://github.com/caddyserver/caddy)
