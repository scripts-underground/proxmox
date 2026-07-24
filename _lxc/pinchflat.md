---
slug: pinchflat
title: Pinchflat
tags: [media, youtube, downloader]
logo: /assets/logos/pinchflat.webp
by: nnsense
repo: https://github.com/kieraneglin/pinchflat
site: https://github.com/kieraneglin/pinchflat
port: 8945
cpu: 2
ram: 2048
disk: 8
maintainer: nnsense
---

A self-hosted YouTube downloader built with Elixir. Automatically monitors channels and playlists, downloads new media via yt-dlp, and provides a web UI for management.

## Notes

- Access the web UI at `http://<ip>:8945` to manage subscriptions and downloads.
- Configure YouTube channel/playlist URLs in the web UI to start downloading.
- Media is downloaded to `/opt/pinchflat/downloads` by default.

## Links

- [GitHub](https://github.com/kieraneglin/pinchflat)
