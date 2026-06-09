---
slug: jellyfin
title: Jellyfin Media Server
tags: [media-streaming]
logo: /assets/logos/jellyfin.webp
by: tteck
repo: https://jellyfin.org/
site: https://jellyfin.org/
port: 8096
cpu: 2
ram: 2048
disk: 16
maintainer: tteck
---

Jellyfin is a free and open-source media server and suite of multimedia applications designed to organize, manage, and share digital media files to networked devices.

## Notes

- With Privileged/Unprivileged Hardware Acceleration Support
- FFmpeg path: /usr/lib/jellyfin-ffmpeg/ffmpeg
- For NVIDIA graphics cards, you'll need to install the same drivers in the container that you did on the host. In the container, run the driver installation script and add the CLI arg --no-kernel-module
- Log rotation is configured in /etc/logrotate.d/jellyfin. To reduce verbosity, change MinimumLevel in /etc/jellyfin/logging.json to Warning or Error (disables fail2ban auth logging).

## Links

- [GitHub](https://github.com/jellyfin/jellyfin)
