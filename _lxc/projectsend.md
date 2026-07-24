---
slug: projectsend
title: ProjectSend
tags: [media]
logo: /assets/logos/projectsend.webp
by: bvdberg01
repo: https://github.com/projectsend/projectsend
site: https://projectsend.org/
port: 80
cpu: 1
ram: 1024
disk: 8
maintainer: bvdberg01
---

Open-source file sharing platform for clients. Supports client groups, user roles, statistics, and multiple languages.

## Notes

- Initial setup at `http://<ip>/install`.
- Runs PHP 8.4 with Apache and MariaDB.
- Database credentials configured automatically in `/opt/projectsend/includes/sys.config.php`.
- Custom PHP limits: memory 256M, post/upload max 256M, execution time 300s.

## Links

- [Website](https://projectsend.org/)
- [GitHub](https://github.com/projectsend/projectsend)
