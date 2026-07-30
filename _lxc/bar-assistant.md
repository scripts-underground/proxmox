---
slug: bar-assistant
title: Bar-Assistant
tags: [cocktails, drinks]
logo: /assets/logos/bar-assistant.webp
by: bvdberg01
co_author: [CanbiZ]
repo: https://github.com/karlomikus/bar-assistant
site: https://barassistant.app/
port: 80
cpu: 2
ram: 2048
disk: 4
maintainer: bvdberg01
---

All-in-one solution for managing your cocktail bar. Bar Assistant is built from the ground up with cocktail recipes in mind, offering powerful features like ingredient substitutes, ABV calculations, bar management, and more.

## Notes

- Access the web UI at `http://{ip}` to complete setup.
- The frontend (Salt Rim) and API (Bar Assistant) are served via nginx on port 80.
- Meilisearch provides full-text search capabilities.
- Redis is used for caching and sessions.

## Links

- [GitHub](https://github.com/karlomikus/bar-assistant)
- [Website](https://barassistant.app/)
- [Salt Rim (Frontend)](https://github.com/karlomikus/vue-salt-rim)
