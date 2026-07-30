---
slug: neo4j
title: Neo4j
tags: [database]
logo: /assets/logos/neo4j.webp
by: tteckster
co_author: [havardthom]
repo: https://github.com/neo4j/neo4j
site: https://neo4j.com/
port: 7474
cpu: 1
ram: 1024
disk: 4
maintainer: tteckster
---

Graph database platform with complete data platform capabilities.

## Notes

- Access the Neo4j Browser at `http://{ip}:7474`.
- Initial connection requires setting a password using `cypher-shell` or the web UI.
- Listens on all interfaces after installation; adjust `server.default_listen_address` in `/etc/neo4j/neo4j.conf` to restrict.

## Links

- [Website](https://neo4j.com/)
- [GitHub](https://github.com/neo4j/neo4j)
