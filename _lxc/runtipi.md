---
slug: runtipi
title: Runtipi
tags: [docker, hosting]
logo: /assets/logos/runtipi.webp
by: MickLesk
repo: https://github.com/runtipi/runtipi
site: https://runtipi.io/
port: 80
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

Runtipi is a self-hosted PaaS solution for deploying and managing applications with an intuitive web interface. It uses Docker under the hood to orchestrate app deployments.

## Notes

- Access the web UI at `http://{ip}` to get started.
- Runtipi uses Docker to manage deployments. The `setup_docker` function handles Docker installation.
- The installer pulls an external script from https://runtipi.io/ which is not maintained or audited by our repository.

## Links

- [Website](https://runtipi.io/)
- [GitHub](https://github.com/runtipi/runtipi)
