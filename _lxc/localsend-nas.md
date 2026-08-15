---
slug: localsend-nas
title: LocalSend NAS
tags: [file-sharing, localsend]
logo: /assets/logos/localsend-nas.webp
by: alexindigo
repo: https://github.com/alexindigo/localsend-nas
site: https://github.com/alexindigo/localsend-nas
port: 80
cpu: 1
ram: 512
disk: 4
maintainer: alexindigo
---

Send-only LocalSend node with a web UI, built for NAS-style deployments: browse host-mounted share directories in a browser, assemble a basket of files, pick a discovered device, and the server sends files directly to the recipient's LocalSend app — files never round-trip through your laptop.

## Notes

- Web UI on port 80; LocalSend protocol v2.2 on 53317 (TCP+UDP multicast discovery) — works on bridged LXC networking (vmbr0).
- Configure shares at install: `var_lxc_shares="movies=/srv/movies,books=/srv/books"` — each is bind-mounted read-only into the CT at `/data/<name>` via `post_build_script`.
- With no shares configured the web UI still runs; add mounts later with `pct set <ctid> -mp0 /srv/share,mp=/data/share,ro=1` and list them in `LOCALSEND_NAS_SHARES` in the systemd unit.
- Health endpoints for monitoring: `/api/health` and `/api/selftest`.

## Links

- [GitHub](https://github.com/alexindigo/localsend-nas)
- [LocalSend](https://localsend.org)
