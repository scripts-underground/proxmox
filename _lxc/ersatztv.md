---
slug: ersatztv
title: ErsatzTV
tags: [iptv]
logo: /assets/logos/ersatztv.webp
by: MickLesk
repo: https://github.com/ErsatzTV/ErsatzTV
site: https://ersatztv.org/
port: 8409
cpu: 2
ram: 1024
disk: 5
maintainer: MickLesk
---

ErsatzTV is a custom IPTV solution for playing custom video streams using FFmpeg.

## Notes

- Access the web UI at `http://{ip}:8409` to complete setup.
- Hardware acceleration is automatically detected and configured for supported GPUs (Intel/AMD/NVIDIA).
- Set `var_gpu="yes"` before installation to enable GPU passthrough.

## Links

- [GitHub](https://github.com/ErsatzTV/ErsatzTV)
- [Website](https://ersatztv.org/)
