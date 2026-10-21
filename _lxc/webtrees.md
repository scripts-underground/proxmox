---
slug: webtrees
title: Webtrees
tags: [genealogy, cms]
logo: /assets/logos/webtrees.webp
by: sudofly
repo: https://github.com/fisharebest/webtrees
site: https://webtrees.net/
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: sudofly
---

Online genealogy application for managing and sharing family tree data. Supports GEDCOM import/export, multi-user collaboration, and media management.

## Notes

- Access the web UI at `http://<ip>` to get started.
- Admin credentials are stored in `~/webtrees.creds` on the container.
- Default admin username is `Admin` with a random password generated during install.
- Make sure to change the admin email and password after first login.
- Caddy denies direct access to private application/data directories; media privacy is enforced through Webtrees. Updates repair this routing even when the app version is unchanged, validating the candidate before publishing or reloading it and retaining custom configuration on validation failure.

## Links

- [Website](https://webtrees.net/)
- [GitHub](https://github.com/fisharebest/webtrees)
