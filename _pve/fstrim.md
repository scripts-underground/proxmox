---
slug: fstrim
title: PVE LXC Filesystem Trim
tags: [proxmox, storage, trim, lxc]
logo: /assets/logos/fstrim.webp
maintainer: community-scripts
---

Releases unused blocks from LXC container disks back to the storage device. Recommended for SSD, NVMe, and thin-provisioned storage.

## Notes

- Only effective on SSD, NVMe, thin-LVM, or discard-capable storage
- Select containers to exclude from trimming
- Can temporarily start stopped containers for trimming

## Links

- [GitHub](https://github.com/community-scripts/ProxmoxVED)
