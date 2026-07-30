---
slug: speedtest-tracker
title: Speedtest Tracker
tags: [monitoring]
logo: /assets/logos/speedtest-tracker.webp
by: AlphaLawless
repo: https://github.com/alexjustesen/speedtest-tracker
site: https://github.com/alexjustesen/speedtest-tracker
port: 80
cpu: 2
ram: 2048
disk: 4
maintainer: AlphaLawless
---

Self-hosted internet performance tracking application that runs speedtest
schedules against Ookla's Speedtest CLI and graphs the results.

## Notes

- Access the web UI at `http://{ip}` to view speedtest results.
- Speedtests run automatically every 6 hours by default.
- Configuration is stored in `/opt/speedtest-tracker/.env`.

## Links

- [GitHub](https://github.com/alexjustesen/speedtest-tracker)
