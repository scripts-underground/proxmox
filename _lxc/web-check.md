---
slug: web-check
title: Web Check
tags: [network, analysis]
logo: /assets/logos/web-check.webp
by: CrazyWolf13
repo: https://github.com/Lissy93/web-check
site: https://github.com/Lissy93/web-check
port: 3000
cpu: 2
ram: 2048
disk: 12
maintainer: CrazyWolf13
---

Self-hosted all-in-one OSINT tool for analyzing websites. Check a website's IP address, DNS records, SSL certificates, open ports, server headers, security.txt, technology stack, and more.

## Notes

- Access the web UI at `http://{ip}:3000`.
- Uses Chromium (headless via Xvfb) for screenshot capture.
- API keys for various services (Shodan, SecurityTrails, etc.) can be configured in `/opt/web-check/.env`.

## Links

- [GitHub](https://github.com/Lissy93/web-check)
