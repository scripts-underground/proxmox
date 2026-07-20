---
slug: coolify
title: Coolify
tags: [docker, paas]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/coolify.webp
by: MickLesk
repo: https://github.com/coollabsio/coolify
site: https://coolify.io/
port: 8000
cpu: 2
ram: 4096
disk: 30
maintainer: MickLesk
---

Self-hostable PaaS solution for hosting applications, databases, and services. Deploy anything from static sites to Docker containers with an intuitive web UI.

## Notes

- Access the web UI at `http://<ip>:8000` to complete setup.
- Coolify uses Docker to manage deployments. The `setup_docker` function handles Docker installation.
- Higher resource requirements (4 GB RAM, 30 GB disk) for running multiple applications.

## Links

- [Website](https://coolify.io/)
- [GitHub](https://github.com/coollabsio/coolify)
