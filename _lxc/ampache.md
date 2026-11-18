---
slug: ampache
title: Ampache
tags: [music]
logo: /assets/logos/ampache.webp
by: MickLesk
repo: https://github.com/ampache/ampache
site: https://ampache.org/
port: 80
cpu: 4
ram: 2048
disk: 5
maintainer: MickLesk
---

Web-based audio/video streaming application and file manager. Organizes and streams your music collection through a web interface.

## Notes

- Access the web interface at `http://<ip>/install.php` to complete the initial setup.
- The database schema is pre-loaded — the web installer handles final configuration.
- Supports streaming to multiple clients simultaneously.
- Installer and updater explicitly select the newest stable Ampache 7.x release on PHP 8.4, following upstream's recommended release line. A missing compatible asset fails without falling back to an older release.
- Updates do not migrate existing installations to Ampache 8 or PHP 8.5. A future 7 -> 8 migration requires a separate, explicit decision.

## Links

- [Website](https://ampache.org/)
- [GitHub](https://github.com/ampache/ampache)
