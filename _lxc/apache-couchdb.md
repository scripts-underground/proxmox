---
slug: apache-couchdb
title: Apache CouchDB
tags: [database]
logo: /assets/logos/apache-couchdb.webp
by: tteckster
repo: https://github.com/apache/couchdb
site: https://couchdb.apache.org/
port: 5984
cpu: 2
ram: 4096
disk: 10
maintainer: tteckster
---

Apache CouchDB is a document-oriented NoSQL database that uses JSON for documents, JavaScript for MapReduce queries, and HTTP for an API.

## Notes

- Access the web UI at `http://<ip>:5984/_utils/` to manage your databases.
- Credentials are stored in `~/couchdb.creds` inside the container.
- CouchDB is configured to bind to `0.0.0.0` for external access.
- Updates are handled via the official CouchDB APT repository.

## Links

- [GitHub](https://github.com/apache/couchdb)
- [Website](https://couchdb.apache.org/)
