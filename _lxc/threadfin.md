---
slug: threadfin
title: Threadfin
tags: [media]
logo: /assets/logos/threadfin.webp
by: tteck
repo: https://github.com/Threadfin/Threadfin
site: https://github.com/Threadfin/Threadfin
port: 34400
cpu: 1
ram: 1024
disk: 4
maintainer: tteck
---

M3U proxy for Plex DVR and Emby/Jellyfin Live TV based on xTeVe. Provides channel mapping, filtering, and EPG management for IPTV streams.

## Notes

- Access the web UI at `http://{ip}:34400/web` after installation.
- Requires GPU passthrough for hardware-accelerated transcoding.
- Binary is architecture-specific — amd64 and arm64 are supported.
- `ffmpeg` and `vlc` are installed as dependencies for stream processing.

## Links

- [GitHub](https://github.com/Threadfin/Threadfin)
