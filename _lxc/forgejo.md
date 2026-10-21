---
slug: forgejo
title: Forgejo
tags: [git]
logo: /assets/logos/forgejo.webp
by: tteck
repo: https://codeberg.org/forgejo/forgejo
site: https://forgejo.org/
port: 80
cpu: 2
ram: 2048
disk: 10
maintainer: tteck
---

Forgejo Git service on Debian. Self-hosted lightweight Git repository manager with issue tracking and CI/CD.

Fresh installs serve HTTP on port80 with a non-root service account. Existing
account homes, SSH keys, repository/data paths and configured ports are retained
on update. The fresh git account uses `/home/git`; an existing account is reused.

## Links

- [Website](https://forgejo.org/)
- [Codeberg](https://codeberg.org/forgejo/forgejo)
