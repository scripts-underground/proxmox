---
slug: copyparty
title: Copyparty
tags: [files-downloads]
logo: /assets/logos/copyparty.webp
by: MickLesk
repo: https://github.com/9001/copyparty
site: https://github.com/9001/copyparty
port: 3923
maintainer: MickLesk
---

Copyparty is a lightweight, portable HTTP file server with a browser-based interface. It supports drag-and-drop uploads, downloads, deduplication, media playback, and advanced search, making it ideal for quickly sharing and managing files.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine)
- Update with: `update-copyparty` — Uninstall with: `uninstall-copyparty`
- Re-running the installer offers update/uninstall via the framework guard

### Update sources

With `var_addon_src_url` unset or set to the stock
`https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py`,
updates check GitHub and deploy exactly the selected release through the shared
single-file publisher. Only a no-update result is successful without deployment;
lookup failures retain the pending update for retry.

A saved custom `var_addon_src_url` remains in use on every update. Its version is
operator-managed: no GitHub release check or release-version claim is made for
that source. The custom download, executable mode and ownership are prepared in
a private stage before atomic publication to the configured binary path. Failed
download or publication preparation keeps the old executable and pending update.
Any previous GitHub version marker is invalidated before publishing custom
content, so returning to the stock source cannot skip an update using a stale
managed-version claim. Failure to invalidate that marker also keeps the old
executable and pending update.
Existing configuration, data and access defaults are not changed by either mode.

## Links

- [GitHub](https://github.com/9001/copyparty)
