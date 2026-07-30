---
slug: urbackupserver
title: UrBackup Server
tags: [backup]
logo: /assets/logos/urbackupserver.webp
by: Kristian Skov
repo: https://github.com/uroni/urbackup
site: https://www.urbackup.org/
port: 55414
cpu: 1
ram: 1024
disk: 16
maintainer: Kristian Skov
---

UrBackup is an easy-to-setup open source client/server backup system that, through a combination of image and file backups, accomplishes both data safety and a fast restoration.

## Notes

- Access the web UI at `http://{ip}:55414` to complete setup.
- The container uses FUSE and nesting features for backup functionality.
- Updates are handled via the system package manager (`apt`).

## Links

- [GitHub](https://github.com/uroni/urbackup)
- [Website](https://www.urbackup.org/)
