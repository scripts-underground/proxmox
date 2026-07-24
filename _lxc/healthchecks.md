---
slug: healthchecks
title: healthchecks
tags: [monitoring]
logo: ""
by: MickLesk
repo: https://github.com/healthchecks/healthchecks
site: https://healthchecks.io
port: 443
cpu: 2
ram: 2048
disk: 5
maintainer: MickLesk
---

Open source cron monitoring and alerting service. Monitor cron jobs, scheduled tasks, and recurring processes with email, Slack, SMS, and webhook notifications.

## Notes

- Access the dashboard at `https://<ip>` (via Caddy reverse proxy).
- Healthchecks runs on port 8000 internally, proxied through Caddy on port 443.
- Uses PostgreSQL 16 as the database backend.
- Admin credentials saved to `~/healthchecks.creds`.
- Two systemd services: `healthchecks` (web UI/API) and `healthchecks-sendalerts` (alert sender).

## Links

- [GitHub](https://github.com/healthchecks/healthchecks)
