---
slug: prometheus-paperless-ngx-exporter
title: Prometheus Paperless-ngx Exporter
tags: [monitoring, documents]
logo: /assets/logos/prometheus-paperless-ngx-exporter.webp
by: andygrunwald
repo: https://github.com/hansmi/prometheus-paperless-exporter
site: https://github.com/hansmi/prometheus-paperless-exporter
port: 8081
maintainer: andygrunwald
---

Prometheus exporter for Paperless-ngx. Scrapes the Paperless-ngx API and exposes document, tag, correspondent, storage path, task, and processing statistics as Prometheus metrics, ready to be scraped by a Prometheus server.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) — typically installed into the Paperless-ngx LXC itself
- Prompts for the Paperless-ngx URL and an API authentication token (stored in `/etc/prometheus-paperless-ngx-exporter/`)
- Metrics endpoint: `http://<container-ip>:8081/metrics`
- Update with: `update-prometheus-paperless-ngx-exporter` — Uninstall with: `uninstall-prometheus-paperless-ngx-exporter`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [GitHub](https://github.com/hansmi/prometheus-paperless-exporter)
- [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx)
