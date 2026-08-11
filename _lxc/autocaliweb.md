---
slug: autocaliweb
title: Autocaliweb
tags: [ebooks]
logo: /assets/logos/autocaliweb.webp
by: vhsdream
repo: https://codeberg.org/gelbphoenix/autocaliweb
site: https://codeberg.org/gelbphoenix/autocaliweb
port: 80
cpu: 2
ram: 2048
disk: 6
maintainer: vhsdream
---

ACW (Autocaliweb) is a web-based ebook management and conversion server with KOReader sync support. It integrates with Calibre and Kepubify for ebook management.

## Notes

- Access the web UI at `http://<ip>` to complete setup.
- Default configuration uses `/opt/calibre-library` for Calibre library and `/opt/acw-book-ingest` for ingest directory.
- Four systemd services are created: `autocaliweb`, `acw-ingest-service`, `acw-auto-zipper`, and `metadata-change-detector`.

## Links

- [Codeberg](https://codeberg.org/gelbphoenix/autocaliweb)
