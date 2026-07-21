---
slug: pocketid
title: PocketID
tags: [identity-provider]
logo: /assets/logos/pocketid.webp
by: Snarkenfaugister
repo: https://github.com/pocket-id/pocket-id
site: https://pocket-id.org
port: 1411
cpu: 2
ram: 2048
disk: 4
maintainer: Snarkenfaugister
---

Simple OIDC provider that allows users to authenticate with passkeys.

## Notes

- Access the setup page at `https://<public_url>/setup`.
- The `.env` file is at `/opt/pocket-id/.env`.
- The service listens on port 1411 — configure your reverse proxy accordingly.

## Links

- [GitHub](https://github.com/pocket-id/pocket-id)
- [Website](https://pocket-id.org)
