---
slug: localsend-nas
title: LocalSend-NAS
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
- The CT's `/opt` directory is the default share root (`LOCALSEND_NAS_SHARES=files=/opt`). Mount your storage anywhere under `/opt` — bind mount, NFS, virtiofs, your call — and it shows up in the picker with no config changes. The app itself lives there too (open source, read-only is fine).
- Health endpoints for monitoring: `/api/health` and `/api/selftest`.

## Links

- [GitHub](https://github.com/alexindigo/localsend-nas)
- [LocalSend](https://localsend.org)
