---
slug: ots
title: OTS
tags: [secrets-sharer]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/ots.webp
by: bvdberg01
repo: https://github.com/Luzifer/ots
site: https://github.com/Luzifer/ots
port: 443
cpu: 1
ram: 512
disk: 3
maintainer: bvdberg01
---

A one-time-secret sharing tool that allows sharing secrets via a temporary link that self-destructs after being read.

## Notes

- Access the web UI at `https://<ip>` (self-signed certificate, browser will show a warning).
- Secrets expire automatically after 7 days (configurable via `SECRET_EXPIRY` in `/opt/ots/.env`).
- Requires nginx and Redis — both are installed and configured automatically.

## Links

- [GitHub](https://github.com/Luzifer/ots)
