---
slug: zipline
title: Zipline
tags: [file, sharing]
logo: /assets/logos/zipline.webp
by: MickLesk
repo: https://github.com/diced/zipline
site: https://zipline.diced.me
port: 3000
cpu: 2
ram: 2048
disk: 5
maintainer: MickLesk
---

A self-hosted file sharing platform built with Node.js.

## Notes

- Access the web UI at `http://<ip>:3000` to get started.
- The application uses PostgreSQL for data storage.
- Your secret key is saved to `~/zipline.creds` inside the container.
- Uploads are stored in `/opt/zipline-uploads` by default.

## Links

- [GitHub](https://github.com/diced/zipline)
- [Website](https://zipline.diced.me)
