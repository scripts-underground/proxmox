---
slug: apache-guacamole
title: Apache Guacamole
tags: [webserver, remote]
logo: /assets/logos/apache-guacamole.webp
by: michelroegl-brunner
co_author: [MickLesk (CanbiZ)]
repo: https://github.com/apache/guacamole-server
site: https://guacamole.apache.org/
port: 8080
cpu: 1
ram: 2048
disk: 4
maintainer: michelroegl-brunner
---

Apache Guacamole is a clientless remote desktop gateway. It supports standard protocols like VNC, RDP, and SSH over the web. No clients or plugins are required — just a web browser.

## Notes

- Access the web UI at `http://{ip}:8080/guacamole` to log in.
- Default credentials are configured during MySQL setup via `guacamole.properties`.
- Guacamole Server (guacd) is built from source. Updates via this script rebuild from the latest upstream tag.
- Tomcat and the Guacamole Client WAR are updated separately by the update script.

## Links

- [GitHub](https://github.com/apache/guacamole-server)
- [Website](https://guacamole.apache.org/)
