---
slug: musicseerr
title: MusicSeerr
tags: [arr, media]
logo: /assets/logos/musicseerr.webp
by: michelroegl-brunner
repo: https://github.com/HabiRabbu/Musicseerr
site: https://musicseerr.com
port: 8688
cpu: 2
ram: 4096
disk: 8
maintainer: michelroegl-brunner
---

Music request and discovery platform for browsing, requesting, playing, and discovering music from your library and supported services.

## Notes

- Access the web UI at `http://<ip>:8688`
- On first launch, create an admin account, then configure your library and download client in Settings

## Configuration and storage

The installed service uses `/opt/musicseerr/backend` as its application root. Configuration lives in `/opt/musicseerr/backend/config`; cache lives in `/opt/musicseerr/backend/cache`.

Retain and back up both directories. Although artwork and metadata caches can be rebuilt, the currently selected upstream release also stores `library.db` under the cache directory. Do not treat the entire cache directory as disposable or remove it to clear cached images.

## Links

- [Website](https://musicseerr.com)
- [GitHub](https://github.com/HabiRabbu/Musicseerr)
- [Documentation](https://musicseerr.com/docs)
