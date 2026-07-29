---
slug: calibre-web-automated
title: Calibre-Web-Automated
tags: [media, books]
logo: /assets/logos/calibre-web-automated.webp
by: alexindigo
repo: https://github.com/crocodilestick/Calibre-Web-Automated
site: https://github.com/crocodilestick/Calibre-Web-Automated
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: alexindigo
---

Calibre-Web-Automated (CWA) is a heavily extended fork of Calibre-Web that turns it into an all-in-one self-hosted digital library. On top of the stock Calibre-Web feature set it adds automatic ingest of new books, automatic format conversion, cover and metadata enforcement, an EPUB fixer, KOReader progress sync, OAuth 2.0/OIDC authentication, smart duplicate detection, and more.

## Notes

- Access the web UI at `http://<ip>` to complete setup. Default admin login is `admin` / `admin123`.
- The Calibre library lives at `/opt/calibre-library`; drop new books into `/opt/cwa-book-ingest` and they will be ingested automatically.
- Configuration (including `app.db`) lives at `/etc/calibre-web-automated`.
- Four systemd services are created: `calibre-web-automated`, `cwa-ingest`, `cwa-metadata-detector`, and `cwa-auto-zipper`.
- Calibre and kepubify are installed system-wide (`/opt/calibre` and `/usr/bin/kepubify`) and used for eBook conversion.

## Links

- [GitHub](https://github.com/crocodilestick/Calibre-Web-Automated)
- [Wiki](https://github.com/crocodilestick/Calibre-Web-Automated/wiki)
