---
slug: reitti
title: Reitti
tags: [location-tracker]
logo: /assets/logos/reitti.webp
by: MickLesk
repo: https://github.com/dedicatedcode/reitti
site: https://www.dedicatedcode.com/projects/reitti/
port: 8080
cpu: 2
ram: 4096
disk: 15
maintainer: MickLesk
---

Self-hosted location tracking and analysis platform. Detects significant places, trip patterns, and integrates with OwnTracks, GPSLogger, and Immich. Uses PostgreSQL + PostGIS and Redis.

## Notes

- Access the web UI at `http://<ip>:8080`.
- Default credentials: `admin` / `admin`.
- Configuration file is at `/opt/reitti/application.properties`.
- Nginx tile cache is configured and running on port 80.

## Links

- [Website](https://www.dedicatedcode.com/projects/reitti/)
- [GitHub](https://github.com/dedicatedcode/reitti)
