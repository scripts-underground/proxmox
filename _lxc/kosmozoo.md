---
slug: kosmozoo
title: Kosmozoo
tags: [comfyui, review, curation]
logo: https://raw.githubusercontent.com/alexindigo/kosmozoo/main/logo-512.png
by: alexindigo
repo: https://github.com/alexindigo/kosmozoo
site: https://github.com/alexindigo/kosmozoo
port: 80
cpu: 1
ram: 512
disk: 2
maintainer: alexindigo
---

Kosmozoo is a zero-build review & curation tool for ComfyUI image output. A Python-stdlib server proxies one or more ComfyUI hosts and serves a single-page app; every judgment (notes, thumbs, buckets, tags) lands in one canonical `feedback.json` that downstream tooling consumes directly.

## Notes

- No build step, no dependencies: pure Python stdlib (`http.server`) + a single inline-JS page.
- Set your ComfyUI hosts with `var_lxc_comfyui_hosts="studio=comfyui.lan:8188,gpu2=192.168.1.5:8188"` (label → host:port, comma-separated).
- `feedback.json` lives at `/opt/kosmozoo/data/feedback.json`; downloads at `/opt/kosmozoo/downloads/`.
- No authentication by design — deploy on trusted LANs only.
- Optional server-side face detection (torch CPU venv) is documented upstream; not installed by default.

## Links

- [GitHub](https://github.com/alexindigo/kosmozoo)
