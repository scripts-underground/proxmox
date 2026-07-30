---
slug: passbolt
title: Passbolt
tags: [auth]
logo: /assets/logos/passbolt.webp
by: tremor021
repo: https://github.com/passbolt/passbolt_api
site: https://www.passbolt.com/
port: 443
cpu: 2
ram: 2048
disk: 2
maintainer: tremor021
---

Open-source password manager designed for teams and businesses.

## Notes

- Access the web UI at `https://{ip}` to complete setup.
- A self-signed SSL certificate is generated automatically. You can replace it with a proper certificate using certbot.
- MariaDB is configured automatically with a `passboltdb` database and `passbolt` user.
- Updates are handled via `apt update && apt upgrade`.

## Links

- [GitHub](https://github.com/passbolt/passbolt_api)
- [Website](https://www.passbolt.com/)
