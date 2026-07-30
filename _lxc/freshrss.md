---
slug: freshrss
title: FreshRSS
tags: [RSS]
logo: /assets/logos/freshrss.webp
by: bvdberg01
repo: https://github.com/FreshRSS/FreshRSS
site: https://freshrss.org
port: 80
cpu: 2
ram: 1024
disk: 4
maintainer: bvdberg01
---

A free, self-hostable RSS feed aggregator. FreshRSS is a lightweight RSS reader with support for multiple users, filtering, search, OPML import/export, and extensions.

## Notes

- Access the web UI at `http://{ip}` (port 80).
- Runs on Apache with PHP 8.4 and PostgreSQL 16.
- Feed refresh happens via cron every 15 minutes — edit `/etc/cron.d/freshrss-actualize` to change.
- First-time setup is done through the web UI.
- Updates preserve data and extensions.

## Links

- [Website](https://freshrss.org)
- [GitHub](https://github.com/FreshRSS/FreshRSS)
- [Documentation](https://freshrss.github.io/FreshRSS/)
