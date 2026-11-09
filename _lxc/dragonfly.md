---
slug: dragonfly
title: Dragonfly
tags: [database, cache]
logo: /assets/logos/dragonfly.webp
by: CanbiZ
repo: https://github.com/dragonflydb/dragonfly
site: https://www.dragonflydb.io/
port: 6379
cpu: 2
ram: 1024
disk: 4
maintainer: CanbiZ
---

Dragonfly is a multithreaded in-memory data store compatible with Redis and Memcached APIs.

## Notes

- Connect with `redis-cli -h <container-ip> -p 6379 --askpass`. Read the generated password from `--requirepass` in `/etc/dragonfly/dragonfly.conf` inside the container.
- The Debian package runs as `dfly`, with data in `/var/lib/dragonfly` and configuration in `/etc/dragonfly`. Snapshots run every 30 minutes.
- Updates preserve configuration, credentials, data and systemd drop-ins. Run `update` inside the container; `update --clean` reinstalls the selected release.
- The required `/etc/dragonfly/scripts-underground-runtime.env` sets disk-backed temporary storage. Keep it and the app-owned `scripts-underground.conf` drop-in when customizing the service.
- Dragonfly requires at least 256 MiB of configured maximum memory per proactor thread. Automatic sizing uses available memory and cgroup limits; review memory when changing CPU allocation.
- Writes fail when memory fills by default. For cache use, configure `--cache_mode=true` and restart the service.

## Links

- [Documentation](https://www.dragonflydb.io/docs)
- [GitHub](https://github.com/dragonflydb/dragonfly)
