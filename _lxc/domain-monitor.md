---
slug: domain-monitor
title: Domain-Monitor
tags: [proxy]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/domain-monitor.webp
by: tremor021
repo: https://github.com/Hosteroid/domain-monitor
site: https://github.com/Hosteroid/domain-monitor
port: 80
cpu: 2
ram: 512
disk: 2
maintainer: tremor021
---
A self-hosted PHP domain expiration monitoring tool that tracks domain expiry dates, RDAP/WHOIS data, and SSL certificate validity. Supports alerts, multi-user setup, and cron automation.
## Notes
- Web UI runs on port 80.
- Configuration file: `/opt/domain-monitor/.env`
- Domain checking cron runs daily at midnight as www-data.
## Links
- [Website](https://github.com/Hosteroid/domain-monitor)
