---
slug: recyclarr
title: Recyclarr
tags: [arr]
logo: /assets/logos/recyclarr.webp
by: MrYadro
repo: https://github.com/recyclarr/recyclarr
site: https://recyclarr.dev/wiki/
port: 0
cpu: 1
ram: 512
disk: 2
maintainer: MrYadro
---

CLI tool that synchronizes recommended TRaSH Guide quality profiles and custom formats to Sonarr and Radarr instances.

## Notes

- No web UI — CLI only. SSH into the container to use.
- Run `recyclarr config create` to generate an initial config.
- A daily cron job runs `recyclarr sync` automatically.
- Edit `/root/.config/recyclarr/recyclarr.yml` to configure your instances.

## Links

- [Website](https://recyclarr.dev/wiki/)
- [GitHub](https://github.com/recyclarr/recyclarr)
