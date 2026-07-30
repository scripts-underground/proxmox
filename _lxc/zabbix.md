---
slug: zabbix
title: Zabbix
tags: [monitoring]
logo: /assets/logos/zabbix.webp
by: CanbiZ
repo: https://github.com/zabbix/zabbix
site: https://www.zabbix.com/
port: 80
cpu: 2
ram: 4096
disk: 6
maintainer: CanbiZ
---

An enterprise-class open-source distributed monitoring solution for networks and applications.

## Notes

- Access the web UI at `http://{ip}/zabbix` to complete setup.
- The installer will prompt for Zabbix version (7.0 LTS, 7.4 Stable, or Latest).
- Choose between Zabbix Agent (classic) or Zabbix Agent2 (modern).
- Agent2 can optionally install all plugins.
- Uses PostgreSQL as the database backend.

## Links

- [GitHub](https://github.com/zabbix/zabbix)
- [Website](https://www.zabbix.com/)
