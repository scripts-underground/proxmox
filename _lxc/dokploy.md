---
slug: dokploy
title: Dokploy
tags: [docker, paas]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/dokploy.webp
by: MickLesk
repo: https://github.com/Dokploy/dokploy
site: https://dokploy.com/
port: 3000
cpu: 2
ram: 2048
disk: 10
maintainer: MickLesk
---

Self-hostable PaaS solution for deploying and managing applications, databases, and services using Docker.

## Notes

- Access the web UI at `http://<ip>:3000` to complete setup.
- Dokploy uses Docker to manage deployments. The `setup_docker` function handles Docker installation.
- Requires a privileged container for Docker functionality.

## Links

- [Website](https://dokploy.com/)
- [GitHub](https://github.com/Dokploy/dokploy)
