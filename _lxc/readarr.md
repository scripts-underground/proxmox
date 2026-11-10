---
slug: readarr
title: Readarr
tags: [media, comic, ebook]
logo: /assets/logos/readarr.webp
by: tteck
repo: https://github.com/Readarr/Readarr
site: https://readarr.com/
port: 8787
cpu: 2
ram: 1024
disk: 4
maintainer: tteck
---

Retired book and audiobook collection manager, retained as a test installer pinned to official GNU release v0.4.18.2805. Metadata lookup and book acquisition are not qualified; the script updates OS packages only, not Readarr.

## Notes

- Access the web UI at `http://<ip>:8787` to configure download clients and indexers.
- Installs the pinned first-party GNU x64 or arm64 archive after checking its architecture-specific SHA256 before extraction.
- Readarr is retired/archived. UI availability does not establish a working metadata backend; the recorded Hobbit lookup returned HTTP503. No metadata workaround is installed.
- The generated update command runs APT update/upgrade only. It does not update the Readarr application or promise ongoing application updates.

## Links

- [Website](https://readarr.com/)
- [GitHub](https://github.com/Readarr/Readarr)
