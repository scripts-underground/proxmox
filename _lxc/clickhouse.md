---
slug: clickhouse
title: ClickHouse
tags: [database]
logo: /assets/logos/clickhouse.webp
by: MickLesk
repo: https://github.com/ClickHouse/ClickHouse
site: https://clickhouse.com/
port: 8123
cpu: 2
ram: 4096
disk: 10
maintainer: MickLesk
---

ClickHouse is an open-source, high-performance columnar database management system designed for real-time analytics and data processing using SQL queries.

## Notes

- The default user 'default' has no password. Set a password for production use.
- During setup you can optionally install ClickStack (HyperDX UI + OTel Collector + MongoDB) for full observability. This requires 4 CPU, 8GB RAM, and 30GB disk.

## Links

- [Website](https://clickhouse.com/)
- [GitHub](https://github.com/ClickHouse/ClickHouse)
- [Documentation](https://clickhouse.com/docs/)
