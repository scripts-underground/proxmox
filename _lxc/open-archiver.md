---
slug: open-archiver
title: Open-Archiver
tags: [os]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/open-archiver.webp
by: tremor021
repo: https://github.com/LogicLabs-OU/OpenArchiver
site: https://openarchiver.com/
port: 3000
cpu: 2
ram: 3072
disk: 8
maintainer: tremor021
---

Open Archiver is a secure, self-hosted email archiving solution. Enables full-text search across email and attachments — create a permanent, searchable, and compliant mail archive from Google Workspace, Microsoft 365, and any IMAP server.

## Notes

- Access the web UI at `http://<ip>:3000` to complete setup.
- PostgreSQL is used as the primary database for metadata and email content.
- Meilisearch provides full-text search capabilities.
- Valkey (Redis-compatible) is used for job queues and caching.
- Open Archiver stores archived email data in `/opt/openarchiver-data`.

## Links

- [Website](https://openarchiver.com/)
- [GitHub](https://github.com/LogicLabs-OU/OpenArchiver)
