---
slug: restic-rest-server
title: Restic REST Server
tags: [backup]
logo: /assets/logos/restic-rest-server.webp
by: alexindigo
repo: https://github.com/restic/rest-server
site: https://github.com/restic/rest-server
port: 80
cpu: 1
ram: 512
disk: 8
maintainer: alexindigo
---

REST backend for restic backups. Single Go binary — point your restic clients at it as a repository endpoint. Data is stored on disk in /opt/rest-server/data/.
