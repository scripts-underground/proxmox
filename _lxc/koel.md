---
slug: koel
title: Koel
tags: [music, streaming]
logo: /assets/logos/koel.webp
by: MickLesk
co_author: [CanbiZ]
repo: https://github.com/koel/koel
site: https://koel.dev/
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

Personal music streaming server. A web-based personal audio streaming service written in Vue on the frontend and Laravel on the backend.

## Notes

- Access the web UI at `http://<ip>` (port 80).
- Runs on Nginx with PHP 8.4 FPM and PostgreSQL 16.
- Media files go in `/opt/koel_media`; scanning runs hourly via cron.
- Supports MusicBrainz, Last.fm, Spotify, and YouTube metadata lookups.

## Links

- [Website](https://koel.dev/)
- [GitHub](https://github.com/koel/koel)
