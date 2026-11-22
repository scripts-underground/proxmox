---
slug: bytestash
title: ByteStash
tags: [code]
logo: /assets/logos/bytestash.webp
by: tremor021
repo: https://github.com/jordan-dalby/ByteStash
site: https://github.com/jordan-dalby/ByteStash
port: 3000
cpu: 2
ram: 2048
disk: 4
maintainer: tremor021
---

A self-hosted web application to store, organise, and manage code snippets efficiently.

## Notes

- Access the web UI at `http://<ip>:3000`.
- New accounts are not admins. After registering, explicitly grant an intended account admin access inside the LXC: `cd /opt/bytestash/server && node src/scripts/admin.js grant <username>`.
- Since upstream v1.6.2, `ADMIN_USERNAMES` is ignored. Existing environment-only admin grants are not migrated automatically; use the CLI command for each intended admin. The updater does not remove or rewrite your setting.
- Snippets are stored under `/opt/bytestash/data/snippets`. The installer's JWT secret is retained in the root-only `/etc/systemd/system/bytestash-backend.service`; include it in private backups. Existing upstream-generated secrets inside the data directory are also preserved.
- Updates preserve the current data directory and leave legacy `/opt/data` in place.

## Links

- [GitHub](https://github.com/jordan-dalby/ByteStash)
- [Releases](https://github.com/jordan-dalby/ByteStash/releases)
