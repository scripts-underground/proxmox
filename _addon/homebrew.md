---
slug: homebrew
title: Homebrew
tags: [misc]
logo: /assets/logos/homebrew.webp
by: MorganCSIT
co_author: [MickLesk (CanbiZ)]
repo: https://github.com/Homebrew/brew
site: https://brew.sh
maintainer: MickLesk
---

Homebrew is the Missing Package Manager for macOS (or Linux). This addon installs Linuxbrew into an existing container, including build dependencies, the `/home/linuxbrew` prefix, and shell integration (`/etc/profile.d` plus the user's `.bashrc`/`.profile`) for a non-root user.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Homebrew cannot run as root — the installer detects the first non-root user (uid >= 1000) or offers to create a `brew` user
- Update with: `update-homebrew` — Uninstall with: `uninstall-homebrew`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://brew.sh)
- [GitHub](https://github.com/Homebrew/brew)
