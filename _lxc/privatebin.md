---
slug: privatebin
title: PrivateBin
tags: [paste, secure]
logo: /assets/logos/privatebin.webp
by: opastorello
repo: https://github.com/PrivateBin/PrivateBin
site: https://privatebin.info/
port: 443
cpu: 1
ram: 1024
disk: 4
maintainer: opastorello
---

Minimalist, open-source online pastebin with end-to-end encryption. Data is encrypted and decrypted in the browser using AES 256-bit keys.

## Notes

- Access the web UI at `https://{ip}` (HTTPS with self-signed certificate).
- Pastes are encrypted client-side; the server never sees the plaintext content.
- Supports discussion mode, file uploads, and expiration settings.

## Links

- [GitHub](https://github.com/PrivateBin/PrivateBin)
- [Website](https://privatebin.info/)
