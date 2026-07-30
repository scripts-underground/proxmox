---
slug: smokeping
title: SmokePing
tags: [network]
logo: /assets/logos/smokeping.webp
by: tteckster
repo: https://github.com/oetiker/SmokePing
site: https://oss.oetiker.ch/smokeping/
port: 80
cpu: 1
ram: 512
disk: 2
maintainer: tteckster
---

Latency measurement tool. Measures, stores and displays latency, latency distribution and packet loss. Uses RRDtool for data storage and visualization.

## Notes

- Access the web UI at `http://{ip}/smokeping`
- Edit targets in `/etc/smokeping/config.d/Targets`
- Default targets include localhost, Google DNS (8.8.8.8), and Cloudflare DNS (1.1.1.1)
- Add custom targets by editing the Targets file and restarting SmokePing with `systemctl restart smokeping`

## Links

- [Website](https://oss.oetiker.ch/smokeping/)
- [GitHub](https://github.com/oetiker/SmokePing)
