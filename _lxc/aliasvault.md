---
slug: aliasvault
title: AliasVault
tags: [auth-security]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/aliasvault.webp
by: ProxmoxVED Community
repo: https://github.com/aliasvault/aliasvault
site: https://aliasvault.net/
port: 443
cpu: 4
ram: 6144
disk: 30
maintainer: ProxmoxVED Community
---

AliasVault is an open-source, end-to-end encrypted password manager and email alias service. It features a zero-knowledge architecture where your master password never leaves your device, a built-in SMTP server for alias email addresses, browser extensions with autofill, and native iOS/Android apps.

## Notes

- The initial installation builds AliasVault from source and takes 15-30 minutes. Do not interrupt the process.
- The admin password is auto-generated during installation and displayed in the installation output. Save it immediately.
- To receive alias emails, configure your domain's MX record to point to this server and update PRIVATE_EMAIL_DOMAINS in /opt/aliasvault/.env.

## Links

- [Website](https://aliasvault.net/)
- [GitHub](https://github.com/aliasvault/aliasvault)
- [Documentation](https://docs.aliasvault.net/)
