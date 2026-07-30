---
slug: dawarich
title: Dawarich
tags: [location, tracking, gps]
logo: /assets/logos/dawarich.webp
by: MickLesk
repo: https://github.com/Freika/dawarich
site: https://github.com/Freika/dawarich
port: 3000
cpu: 4
ram: 4096
disk: 15
maintainer: MickLesk
---

Self-hosted web application that allows you to track your location history, import data from various sources (Google Maps, OwnTracks, GPX), and visualize it on an interactive map.

## Notes

- Access the application at `http://{ip}:3000`.
- Data is stored in PostgreSQL with PostGIS extension.
- Background processing via Redis and Sidekiq.
- Supports importing from Google Maps, OwnTracks, GPX, and more.

## Links

- [GitHub](https://github.com/Freika/dawarich)
