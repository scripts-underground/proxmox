---
slug: filebrowser-quantum
title: FileBrowser Quantum
tags: [files, management, web]
logo: /assets/logos/filebrowser-quantum.webp
by: MickLesk
repo: https://github.com/gtsteffaniak/filebrowser
site: https://github.com/gtsteffaniak/filebrowser
port: 8080
maintainer: MickLesk
---

FileBrowser Quantum is an actively maintained fork of the classic File Browser with a modernized UI, real-time indexing and search, and extended media and document previews. It provides web-based upload, download, rename, and share management for the container's filesystem.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Access at `http://<ip>:8080`
- Default credentials: `admin` / `community-scripts.org`
- Supports no-auth mode for local networks
- Indexes the container root filesystem (`/proc`, `/sys`, `/dev`, `/run`, `/tmp` excluded from watching)
- Update with: `update-filebrowser-quantum` — Uninstall with: `uninstall-filebrowser-quantum`

## Links

- [GitHub](https://github.com/gtsteffaniak/filebrowser)
