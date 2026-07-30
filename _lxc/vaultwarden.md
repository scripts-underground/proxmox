---
slug: vaultwarden
title: Vaultwarden
tags: [password-manager]
logo: /assets/logos/vaultwarden.webp
by: tteck
repo: https://github.com/dani-garcia/vaultwarden
site: https://github.com/dani-garcia/vaultwarden
port: 8000
cpu: 4
ram: 6144
disk: 20
maintainer: tteck
---

Vaultwarden is an alternative implementation of the Bitwarden server API written in Rust. Self-hosted, lightweight, and compatible with all Bitwarden clients.

## Notes

- Access the web UI at `https://{ip}:8000` using a self-signed certificate.
- Default self-signed TLS certificate is configured automatically.
- Admin token can be set via the update menu option.
- Supports SQLite, MySQL, and PostgreSQL (SQLite is default).

## Links

- [GitHub](https://github.com/dani-garcia/vaultwarden)
- [Website](https://github.com/dani-garcia/vaultwarden)
