---
slug: kima-hub
title: Kima-Hub
tags: [music, streaming, media]
logo: /assets/logos/kima-hub.webp
by: MickLesk
repo: https://github.com/Chevron7Locked/kima-hub
site: https://github.com/Chevron7Locked/kima-hub
port: 3030
cpu: 4
ram: 8192
disk: 20
maintainer: MickLesk
---

Self-hosted, on-demand audio streaming platform with AI-powered vibe matching, mood detection, smart playlists, and Lidarr/Audiobookshelf integration.

## Notes

- First user to register becomes the administrator.
- Mount your music library to `/music` in the container.
- Audio analysis (mood/vibe detection) requires significant RAM (2-4GB per worker).
- Access the web UI at `http://<ip>:3030` to complete setup.

## Links

- [GitHub](https://github.com/Chevron7Locked/kima-hub)
