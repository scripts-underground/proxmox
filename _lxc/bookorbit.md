---
slug: bookorbit
title: BookOrbit
tags: [books, library, reading]
logo: /assets/logos/bookorbit.webp
by: MickLesk
repo: https://github.com/bookorbit/bookorbit
site: https://bookorbit.app
port: 80
cpu: 2
ram: 4096
disk: 10
maintainer: MickLesk
---
A self-hosted library management and reading platform for ebooks, PDFs, audiobooks, and comics.

## System requirements

Provision 2 CPU cores, 4 GiB RAM and 10 GiB disk for installation and
source-rebuilding updates. The script compiles the Vue/Vite frontend and Nest
backend. This is the supported build requirement, not a measured idle/runtime
minimum. Existing containers are not resized: provision the build RAM before
updating.

Fresh installs use HTTP port80. Complete onboarding with the setup token in
`/root/bookorbit.creds` inside the container. Configuration is
`/opt/bookorbit/.env`; default data is `/opt/bookorbit-data` and libraries may use
`/opt/bookorbit-books`. Keep the original environment and encryption keys with
your backups: replacing keys makes encrypted provider credentials unreadable.

Updates preserve existing ports, URLs, keys and data. Older installations without
`BOOK_REQUEST_ENCRYPTION_KEY` require an operator-generated32-byte hex key before
download-client/indexer credentials can be saved; updates never rotate or add
keys silently. Optional TTS/read-aloud workers are not installed by this script.

Updater discovery supports explicit PostgreSQL URI user/password/database with
DNS, IPv4 or IPv6 hosts, bounded application-name/timeouts and UTF-8 options;
TLS is limited to `sslmode=disable`. Unsupported URI options, TLS settings or
service/PG environment overrides are refused rather than silently downgraded.

## Links
- [GitHub](https://github.com/bookorbit/bookorbit)
- [Website](https://bookorbit.app/)
