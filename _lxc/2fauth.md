---
slug: 2fauth
title: 2FAuth
tags: [2fa, authenticator]
logo: /assets/logos/2fauth.webp
by: jkrgr0
repo: https://github.com/Bubka/2FAuth
site: https://docs.2fauth.app/
port: 80
cpu: 1
ram: 512
disk: 2
maintainer: jkrgr0
---

Self-hosted two-factor authentication manager. Manage and store TOTP tokens, WebAuthn credentials, and backup codes for all your online accounts.

## Notes

- Access the web UI at `http://{ip}` (port 80).
- Runs on Nginx with PHP 8.4 FPM and MariaDB.
- Supports TOTP, HOTP, and WebAuthn/Passkey authentication.

## Links

- [Documentation](https://docs.2fauth.app/)
- [GitHub](https://github.com/Bubka/2FAuth)
