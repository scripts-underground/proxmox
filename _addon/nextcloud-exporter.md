---
slug: nextcloud-exporter
title: Nextcloud-Exporter
tags: [monitoring]
logo: /assets/logos/nextcloud-exporter.webp
by: CrazyWolf13
repo: https://github.com/xperimental/nextcloud-exporter
site: https://github.com/xperimental/nextcloud-exporter
port: 9205
maintainer: CrazyWolf13
---

Nextcloud-Exporter is a Prometheus exporter that scrapes the Nextcloud serverinfo API — storage, shares, users, apps and update information — and exposes the metrics over HTTP for scraping by Prometheus.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) — typically installed inside the Nextcloud LXC itself
- Prompts for the Nextcloud URL and an auth token (or username/password) during install
- Config: `/etc/nextcloud-exporter.env` — Metrics: `http://<container-ip>:9205/metrics`
- Update with: `update-nextcloud-exporter` — Uninstall with: `uninstall-nextcloud-exporter`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/xperimental/nextcloud-exporter)
