---
slug: unbound
title: Unbound
tags: [dns]
logo: /assets/logos/unbound.webp
by: wimb0
repo: https://github.com/NLnetLabs/unbound
site: https://nlnetlabs.nl/projects/unbound/about/
port: 5335
cpu: 1
ram: 512
disk: 2
maintainer: wimb0
---

Unbound is a validating, recursive, caching DNS resolver designed to be fast and lean. It incorporates modern features based on open standards, including DNS-over-TLS, DNS-over-HTTPS, Query Name Minimisation, and aggressive DNSSEC-validated cache usage.

## Notes

- Unbound runs as a recursive DNS resolver on port 5335.
- Access the service at `http://{ip}:5335`.
- Configure your client devices or router to use the container's IP as the DNS server for local network filtering.
- The log file is located at `/var/log/unbound.log` with daily logrotate configured.

## Links

- [Unbound on GitHub](https://github.com/NLnetLabs/unbound)
- [NLnet Labs — Unbound](https://nlnetlabs.nl/projects/unbound/about/)
