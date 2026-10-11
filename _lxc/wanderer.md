---
slug: wanderer
title: Wanderer
tags: [travelling, sport]
logo: /assets/logos/wanderer.webp
by: rrole
repo: https://github.com/open-wanderer/wanderer
site: https://wanderer.to
port: 3000
cpu: 2
ram: 4096
disk: 8
maintainer: rrole
---

Wanderer is a decentralized, self-hosted trail database for uploading GPS tracks, adding metadata, and building a searchable catalogue.

## Notes

- Access the web UI at `http://<ip>:3000` to get started.
- Use `wanderer-pb` instead of `./pocketbase` directly for CLI commands — it ensures environment variables like the encryption key are loaded.
- Provider plugins are installed separately under `/opt/wanderer/data/plugins/{hammerhead,komoot,strava}`. Updates check them even when Wanderer itself is current, so failed or missing plugins can be retried. Plugin failures produce warnings while allowing the application to run.
- Updates preserve plugin configuration and custom plugins. Files left in the shared plugin root by older installations are retained; their presence triggers per-plugin repair instead of treating old version markers as proof of a complete installation.
- The first admin user must be created via `wanderer-pb superuser upsert email@example.com password`.

## Links

- [GitHub](https://github.com/open-wanderer/wanderer)
- [Website](https://wanderer.to)
