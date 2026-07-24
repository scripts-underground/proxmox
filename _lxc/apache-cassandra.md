---
slug: apache-cassandra
title: Apache Cassandra
tags: [database, NoSQL]
logo: /assets/logos/apache-cassandra.webp
by: tteck
repo: https://github.com/apache/cassandra
site: https://cassandra.apache.org/
port: 9042
cpu: 1
ram: 2048
disk: 4
maintainer: tteck
---

Apache Cassandra is a highly-scalable, partitioned-row NoSQL database
engine with linear scalability and fault-tolerance on commodity hardware.

## Notes

- Connect via CQL using `cqlsh` from the container or remotely on port 9042.
- The default CQL port is 9042.
- Configuration lives in `/etc/cassandra/cassandra.yaml`.

## Links

- [GitHub](https://github.com/apache/cassandra)
- [Website](https://cassandra.apache.org/)
