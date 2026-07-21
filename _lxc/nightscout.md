---
slug: nightscout
title: Nightscout
tags: [health]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/nightscout.webp
by: aendel
repo: https://github.com/nightscout/cgm-remote-monitor
site: https://nightscout.github.io
port: 1337
cpu: 2
ram: 2048
disk: 10
maintainer: aendel
---

Cloud-based CGM (Continuous Glucose Monitor) remote monitoring platform. Allows real-time blood sugar data access via browser, provides predictive alerts, and integrates with various diabetes devices and pumps.

## Notes

- Access the dashboard at `http://<ip>:1337`.
- Requires MongoDB — installed automatically.
- API_SECRET saved to `/opt/nightscout/my.env` and `~/nightscout.creds`.
- Customize the ENABLE plugins list post-installation to tailor features.

## Links

- [GitHub](https://github.com/nightscout/cgm-remote-monitor)
- [Documentation](https://nightscout.github.io)
