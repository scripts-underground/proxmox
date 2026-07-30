---
slug: onlyoffice
title: ONLYOFFICE
tags: [word, excel, powerpoint, pdf]
logo: /assets/logos/onlyoffice.webp
by: MickLesk
repo: https://github.com/community-scripts/ProxmoxVE
site: https://www.onlyoffice.com/
port: 80
cpu: 2
ram: 2048
disk: 10
maintainer: MickLesk
---

ONLYOFFICE Document Server is an online office suite with a collaborative editor that allows you to create, edit, and share text, spreadsheet, and presentation files via your browser.

## Notes

- Access the web UI at `http://<ip>` after installation completes.
- Requires PostgreSQL 16 and RabbitMQ — both installed automatically.
- Credentials are stored in `/root/onlyoffice.creds` within the container.
- Updates use `apt --only-upgrade` on the `onlyoffice-documentserver` package.

## Links

- [Website](https://www.onlyoffice.com/)
- [Documentation](https://helpcenter.onlyoffice.com/)
