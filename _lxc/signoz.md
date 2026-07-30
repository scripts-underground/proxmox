---
slug: signoz
title: SigNoz
tags: [notes]
logo: /assets/logos/signoz.webp
by: tremor021
repo: https://github.com/SigNoz/signoz
site: https://signoz.io/
port: 8080
cpu: 2
ram: 4096
disk: 20
maintainer: tremor021
---

SigNoz is an open-source observability platform for monitoring applications, metrics, traces, and logs.

## Notes

- Access the web UI at `http://{ip}:8080` to sign in and configure.
- SigNoz uses ClickHouse as its telemetry store and Zookeeper for orchestration.
- Updates are handled via the update script, which runs schema migrations automatically.

## Links

- [SigNoz on GitHub](https://github.com/SigNoz/signoz)
- [Website](https://signoz.io/)
