---
slug: sqlserver2025
title: SQL Server 2025
tags: [sql, database]
logo: /assets/logos/sqlserver2025.webp
by: MickLesk
repo: https://github.com/microsoft/mssql-server
site: https://www.microsoft.com/en-us/sql-server/sql-server-2025
port: 1433
cpu: 2
ram: 2048
disk: 10
maintainer: MickLesk
---

Microsoft SQL Server 2025 relational database management system for Ubuntu 24.04 LXC containers. Supports T-SQL queries, stored procedures, and integration with Microsoft ecosystem tools.

## Notes

- Access SQL Server at `http://{ip}:1433` using any SQL Server client (e.g., Azure Data Studio, SSMS, mssql-cli).
- Run `/opt/mssql/bin/mssql-conf setup` to configure the SA password and edition.
- SQL Server tools (`sqlcmd`, `bcp`) are installed at `/opt/mssql-tools18/bin/`.
- This is a privileged container (required by SQL Server).
- Updates are handled via `apt upgrade`.

## Links

- [Website](https://www.microsoft.com/en-us/sql-server/sql-server-2025)
- [Microsoft SQL Server Documentation](https://learn.microsoft.com/en-us/sql/)
