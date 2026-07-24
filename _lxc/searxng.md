---
slug: searxng
title: SearXNG
tags: [search]
logo: /assets/logos/searxng.webp
by: MickLesk
repo: https://github.com/searxng/searxng
site: https://github.com/searxng/searxng
port: 8888
cpu: 2
ram: 2048
disk: 7
maintainer: MickLesk
---
Privacy-respecting metasearch engine. Aggregates results from 200+ search services without tracking.
## Notes
- Secret key auto-generated at install.
- Uses Valkey (Redis-compatible) for caching.
- Update uses venv rebuild with --use-pep517.
## Links
- [Documentation](https://docs.searxng.org/)
