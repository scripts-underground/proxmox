---
slug: graylog
title: Graylog
tags: [logging]
logo: /assets/logos/graylog.webp
by: tremor021
repo: https://github.com/Graylog2/graylog2-server
site: https://graylog.org/
port: 9000
cpu: 2
ram: 8192
disk: 30
maintainer: tremor021
---

Centralized log management platform for collecting, indexing, and analyzing log data in real-time.

## Notes

- Access the web UI at `http://{ip}:9000`
- Admin credentials are stored in `~/graylog.creds` inside the container
- Default admin user: `admin`, password: see `~/graylog.creds`
- Requires significant RAM — 8 GB minimum recommended

## Links

- [Website](https://graylog.org/)
- [GitHub](https://github.com/Graylog2/graylog2-server)
- [Documentation](https://go2docs.graylog.org/)
