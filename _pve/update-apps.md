---
slug: update-apps
title: PVE LXC Apps Updater
tags: [proxmox]
logo: /assets/logos/update-apps.webp
by: BvdBerg01
maintainer: community-scripts
---

This script updates community-scripts managed LXC containers on a Proxmox VE node. It detects the installed service, verifies available update scripts, and applies updates interactively or unattended. Optionally, containers can be backed up before the update process.

## Notes

- Execute within the Proxmox shell.
- By default, only containers with `community-script` or `proxmox-helper-scripts` tags are listed for update.
- Optionally performs a vzdump backup before updating containers.
- If required, the script will temporarily increase container CPU/RAM resources for the build process and restore them after completion.
- Supports various environment variables for automation: var_backup, var_backup_storage, var_container, var_unattended, var_skip_confirm, var_auto_reboot.

## Links

- [Discussion](https://github.com/community-scripts/ProxmoxVE/discussions/11532)
