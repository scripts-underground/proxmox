---
slug: fireshare
title: Fireshare
tags: [sharing, video]
logo: /assets/logos/fireshare.webp
by: tremor021
repo: https://github.com/ShaneIsrael/fireshare
site: https://fireshare.net
port: 80
cpu: 2
ram: 2048
disk: 10
maintainer: tremor021
---

Self host your media and share with unique links.

Fireshare lets you share your video content using unique links. Upload videos, generate share links, and let viewers watch without needing an account. Supports hardware-accelerated transcoding with NVIDIA GPUs.

## Notes

- Access the web UI at `http://<ip>` to get started
- Admin credentials are saved to `~/fireshare.creds` inside the container
- For GPU transcoding, set `var_gpu="yes"` before installation and pass through the NVIDIA GPU

## Links

- [GitHub](https://github.com/ShaneIsrael/fireshare)
- [Website](https://fireshare.net)
