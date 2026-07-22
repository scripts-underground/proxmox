---
slug: zitadel
title: Zitadel
tags: [identity-provider]
logo: /assets/logos/zitadel.webp
by: dave-yap
repo: https://github.com/zitadel/zitadel
site: https://zitadel.com/
port: 8080
cpu: 1
ram: 1024
disk: 8
maintainer: dave-yap
---

Open-source identity infrastructure platform. Provides authentication, authorization, and user management for applications.

## Notes

- Access the web console at `http://<ip>:8080/ui/console`.
- PostgreSQL database and credentials are stored in `~/zitadel.creds`.
- After changing `config.yaml`, run `~/zitadel-rerun.sh` to re-apply with the new config.
- Zitadel runs as the `zitadel` user for security.

## Links

- [GitHub](https://github.com/zitadel/zitadel)
- [Website](https://zitadel.com/)
