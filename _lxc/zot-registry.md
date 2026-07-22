---
slug: zot-registry
title: Zot-Registry
tags: [registry, oci]
logo: /assets/logos/zot-registry.webp
by: MickLesk
repo: https://github.com/project-zot/zot
site: https://zotregistry.dev/
port: 8080
cpu: 1
ram: 4096
disk: 5
maintainer: MickLesk
---

OCI Distribution Registry with a web UI for browsing and managing container images and artifacts. Supports OCI-compliant image storage, authentication, and GC.

## Notes

- Access the web UI at `http://<ip>:8080` to browse container images.
- Default admin credentials are stored in `~/zot.creds` inside the container.
- Resource limits: 2 GB memory soft limit, 4 GB hard limit.

## Links

- [Website](https://zotregistry.dev/)
- [GitHub](https://github.com/project-zot/zot)
