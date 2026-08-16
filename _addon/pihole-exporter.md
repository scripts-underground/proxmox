---
slug: pihole-exporter
title: Pi-hole Exporter
tags: [monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/pi-hole.webp
by: CrazyWolf13
repo: https://github.com/eko/pihole-exporter
site: https://github.com/eko/pihole-exporter
port: 9617
maintainer: CrazyWolf13
---

Pi-hole Exporter is a Prometheus exporter for Pi-hole. It connects to the Pi-hole API and exposes statistics — queries forwarded/blocked, clients, top domains, gravity — as Prometheus metrics, ready to be scraped by a Prometheus server and visualized in Grafana.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine) — typically installed into the Pi-hole LXC itself
- Prompts for the Pi-hole connection during install (protocol, hostname, port, password, TLS verification skip) — stored in `/opt/pihole-exporter.env`
- Metrics endpoint: `http://<container-ip>:9617/metrics`
- Update with: `update-pihole-exporter` — Uninstall with: `uninstall-pihole-exporter`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/eko/pihole-exporter)
- [Pi-hole](https://pi-hole.net/)
