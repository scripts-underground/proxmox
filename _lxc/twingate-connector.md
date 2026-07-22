---
slug: twingate-connector
title: Twingate Connector
tags: [network, connector, twingate]
logo: /assets/logos/twingate-connector.webp
by: twingate-andrewb
co_author: [MickLesk]
repo: https://github.com/twingate/connector
site: https://www.twingate.com/
port: 0
cpu: 1
ram: 1024
disk: 3
maintainer: twingate-andrewb
---

Twingate Connector provides secure remote access to your private resources without exposing them to the public internet. It establishes outbound-only connections to Twingate's cloud platform for zero-trust network access.

## Notes

- You will be prompted for your Twingate access token, refresh token, and network name during installation.
- The connector configuration file is located at `/etc/twingate/connector.conf`.
- Access and refresh tokens can be updated by editing the config file and restarting the service.
- The connector does not expose a web UI; it connects outbound to Twingate's cloud.

## Links

- [Website](https://www.twingate.com/)
- [Documentation](https://www.twingate.com/docs/)
