---
slug: alpine-borgbackup-server
title: Alpine-BorgBackup-Server
tags: [alpine, backup]
logo: /assets/logos/alpine-borgbackup-server.webp
by: sanderkoenders
repo: https://github.com/borgbackup/borg
site: https://www.borgbackup.org/
port: 0
cpu: 2
ram: 1024
disk: 20
maintainer: sanderkoenders
---

BorgBackup server on Alpine Linux. Deduplicating backup solution with SSH access for secure remote backups.

## Notes

- No web UI — SSH access only.
- Connect via: `ssh backup@<ip>`
- Set up SSH keys using the update script (option 2).
- Large default disk (20 GB) for backup storage.

## Links

- [Website](https://www.borgbackup.org/)
- [GitHub](https://github.com/borgbackup/borg)
