---
slug: cron-update-lxcs
title: PVE Cron LXC Updater
tags: [proxmox]
logo: /assets/logos/cron-update-lxcs.webp
by: MickLesk
maintainer: community-scripts
---

This script will add/remove a crontab schedule that updates the operating system of all LXCs every Sunday at midnight.

## Notes

- Execute within the Proxmox shell
- To exclude LXCs from updating, edit the crontab using `crontab -e` and add CTID

## Links

- [GitHub](https://github.com/community-scripts/ProxmoxVED)
