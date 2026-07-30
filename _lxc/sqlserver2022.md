---
slug: sqlserver2022
title: SQL Server 2022
tags: [sql]
logo: /assets/logos/sqlserver2022.webp
by: Kristian Skov
repo: https://github.com/community-scripts/ProxmoxVE
site: https://www.microsoft.com/en-us/sql-server/sql-server-2022
port: 1433
cpu: 1
ram: 2048
disk: 10
maintainer: Kristian Skov
---

Microsoft SQL Server 2022 relational database management system.

## Notes

- Access SQL Server at `tcp://{ip}:1433`
- Run SQL Server setup after installation: `/opt/mssql/bin/mssql-conf setup`
- SQL Server tools are available at `/opt/mssql-tools18/bin/`
- This container requires privileged mode (`unprivileged: 0`)

## Links

- [Microsoft SQL Server Website](https://www.microsoft.com/en-us/sql-server/sql-server-2022)
