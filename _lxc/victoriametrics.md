---
slug: victoriametrics
title: VictoriaMetrics
tags: [database]
logo: /assets/logos/victoriametrics.webp
by: tremor021
repo: https://github.com/VictoriaMetrics/VictoriaMetrics
site: https://victoriametrics.com/
port: 8428
cpu: 2
ram: 2048
disk: 16
maintainer: tremor021
---

VictoriaMetrics is a free, open-source time series database and monitoring solution designed for collecting, storing, and querying large volumes of metrics data. It's compatible with Prometheus and offers improved performance and resource efficiency.

## Notes

- Access the web UI at `http://<ip>:8428/vmui` for Prometheus-style querying and visualization.
- Data is stored at `/opt/victoriametrics/data`.
- Updates are handled via the script's update function.

## Links

- [GitHub](https://github.com/VictoriaMetrics/VictoriaMetrics)
- [Website](https://victoriametrics.com/)
