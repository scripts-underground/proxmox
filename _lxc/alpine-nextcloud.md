---
slug: alpine-nextcloud
title: Nextcloud on Alpine
tags: [alpine, cloud]
logo: /assets/logos/alpine-nextcloud.webp
by: tteckster
repo: https://github.com/nextcloud/nextcloud
site: https://nextcloud.com/
port: 443
cpu: 2
ram: 1024
disk: 2
maintainer: tteckster
---

Nextcloud is a suite of client-server software for creating and using file hosting services.

## Notes

- Access the web UI at `https://<ip>` to manage your cloud storage.
- The connection uses a self-signed certificate — your browser will show a security warning.
- Admin and database credentials are stored in `~/nextcloud.creds` inside the container.
- Update the container via the update menu to renew the self-signed certificate if needed.

## Links

- [GitHub](https://github.com/nextcloud/nextcloud)
- [Website](https://nextcloud.com/)
