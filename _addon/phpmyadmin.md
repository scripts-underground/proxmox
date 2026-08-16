---
slug: phpmyadmin
title: phpMyAdmin
tags: [database]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/phpmyadmin.webp
by: MickLesk
repo: https://github.com/phpmyadmin/phpmyadmin
site: https://www.phpmyadmin.net
port: 80
maintainer: MickLesk
---

phpMyAdmin is a PHP web-based administration tool for MySQL and MariaDB. Manage databases, tables, users, import/export SQL — from any browser.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu or Alpine) — not on the PVE host
- Expects a container that already provides a database server (e.g. a MariaDB or MySQL LXC) to administer
- Debian/Ubuntu: installs into the container's existing Apache + PHP stack at `/var/www/html/phpMyAdmin`
- Alpine: installs and configures Lighttpd + PHP-FPM serving phpMyAdmin on port 80
- Update with: `update-phpmyadmin` — Uninstall with: `uninstall-phpmyadmin`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://www.phpmyadmin.net)
- [GitHub](https://github.com/phpmyadmin/phpmyadmin)
