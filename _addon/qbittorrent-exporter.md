---
slug: qbittorrent-exporter
title: qBittorrent-Exporter
tags: [monitoring, arr-suite]
logo: /assets/logos/qbittorrent-exporter.webp
by: CrazyWolf13
repo: https://github.com/martabal/qbittorrent-exporter
site: https://github.com/martabal/qbittorrent-exporter
port: 8090
maintainer: CrazyWolf13
---

qBittorrent-Exporter is a Prometheus exporter for qBittorrent. It scrapes the qBittorrent Web API and exposes transfer, torrent, and tracker metrics at `/metrics` for Prometheus to collect.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine) — typically the qBittorrent LXC itself
- Prompts for the qBittorrent Web UI URL and API key during install (create a key under Tools → Options → Web UI → API key)
- Metrics: `http://<container-ip>:8090/metrics` — Config: `/opt/qbittorrent-exporter.env`
- Update with: `update-qbittorrent-exporter` — Uninstall with: `uninstall-qbittorrent-exporter`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/martabal/qbittorrent-exporter)
