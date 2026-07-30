---
slug: prometheus
title: Prometheus
tags: [monitoring]
logo: /assets/logos/prometheus.webp
by: tteck
repo: https://github.com/prometheus/prometheus
site: https://prometheus.io/
port: 9090
cpu: 1
ram: 2048
disk: 4
maintainer: tteck
---

Prometheus monitoring system and time series database.

## Notes

- Access the web UI at `http://{ip}:9090` to browse metrics and configure queries.
- Configuration file is at `/etc/prometheus/prometheus.yml`.
- Data is stored in `/var/lib/prometheus/`.

## Links

- [GitHub](https://github.com/prometheus/prometheus)
- [Website](https://prometheus.io/)
