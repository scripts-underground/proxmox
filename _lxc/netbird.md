---
slug: netbird
title: NetBird
tags: [network, vpn]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/netbird.webp
by: TechHutTV
repo: https://github.com/netbirdio/netbird
site: https://netbird.io
port: 0
cpu: 1
ram: 512
disk: 4
maintainer: TechHutTV
---

Open source VPN platform built on WireGuard that connects devices into a secure overlay network.

NetBird uses WireGuard encryption to create secure peer-to-peer connections between machines, with automatic key management and routing. It supports setup keys for automated enrollment and SSO authentication via identity providers.

## Notes

- Access NetBird by entering the container and running `netbird up`
- For setup key enrollment: `netbird up -k <setup-key>`
- For self-hosted management: `netbird up --management-url https://your-mgmt-server`
- Requires TUN enabled on the container

## Links

- [GitHub](https://github.com/netbirdio/netbird)
- [Documentation](https://docs.netbird.io)
