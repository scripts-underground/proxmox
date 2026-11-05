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
- Add prepares a self-contained worker from the executing manager for optional
  content/SHA256 review, then installs `/usr/local/bin/update-lxcs.sh`. Cron runs
  this local executable offline. Execute a newer manager and choose Update to
  refresh the worker; existing configuration is retained.
- Set `EXCLUDE=100,101,102` in `/etc/update-lxcs.conf` to exclude decimal CT IDs.
  Spaces and `#` comments are supported; values are parsed literally, never as
  shell code. The worker also accepts excluded IDs as separate arguments, for
  example `/usr/local/bin/update-lxcs.sh 100 101`.
- Templates and unsupported operating systems are explicitly skipped. Supported
  systems are Debian, Ubuntu, Devuan, Alpine, Arch Linux, Fedora, Rocky, CentOS,
  AlmaLinux and openSUSE. This updates OS packages, not application releases.
- Running containers stay running. Selected stopped containers are started only
  after checks, then gracefully shut down with a 60-second timeout and no forced
  stop. A failed start never reaches package work. Failures are reported, later
  independent containers continue, and the worker exits nonzero. A failed
  shutdown can leave a container running and requires operator attention.
- Logs are appended to `/var/log/update-lxcs-cron.log`. Remove keeps the config.

## Links

- [GitHub](https://github.com/community-scripts/ProxmoxVED)
