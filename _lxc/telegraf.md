---
slug: telegraf
title: Telegraf
tags: [collector, metrics]
logo: /assets/logos/telegraf.webp
by: CrazyWolf13
repo: https://github.com/influxdata/telegraf
site: https://www.influxdata.com/time-series-platform/telegraf/
port: 0
cpu: 1
ram: 1024
disk: 4
maintainer: CrazyWolf13
---

Plugin-driven server agent for collecting and reporting metrics. Collects data from over 300 sources and sends to databases, APIs, and message queues.

## Notes

- Installed via the official InfluxData apt repository.
- Configuration file is at `/etc/telegraf/telegraf.conf`.
- Updates are handled via `apt upgrade`.
- Telegraf does not expose a web UI by default.

## Links

- [Website](https://www.influxdata.com/time-series-platform/telegraf/)
- [GitHub](https://github.com/influxdata/telegraf)
