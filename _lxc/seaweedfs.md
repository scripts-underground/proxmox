---
slug: seaweedfs
title: SeaweedFS
tags: [storage, s3, filesystem]
logo: /assets/logos/seaweedfs.webp
by: MickLesk
repo: https://github.com/seaweedfs/seaweedfs
site: https://github.com/seaweedfs/seaweedfs
port: 9333
cpu: 2
ram: 2048
disk: 16
maintainer: MickLesk
---

Distributed file system for storing and serving billions of files quickly and efficiently. Supports S3-compatible object storage, FUSE mount, filer, and NoFUSE modes.

## Notes

- Access the master UI at `http://{ip}:9333`.
- The volume server runs on port `8080` and S3-compatible API on port `8333`.
- Files are stored under `/opt/seaweedfs-data`.
- The `weed` CLI is symlinked to `/usr/local/bin/weed` for administration.

## Links

- [GitHub](https://github.com/seaweedfs/seaweedfs)
