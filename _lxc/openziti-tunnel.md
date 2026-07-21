---
slug: openziti-tunnel
title: OpenZiti-Tunnel
tags: [network, openziti-tunnel]
logo: /assets/logos/openziti-tunnel.webp
by: emoscardini
repo: https://github.com/openziti/ziti
site: https://openziti.io
port: 0
cpu: 1
ram: 512
disk: 2
maintainer: emoscardini
---

OpenZiti edge tunnel. Zero-trust network overlay with identity-based secure connectivity. No open ports, no VPNs — services vanish from the internet.

## Notes

- No web UI — this is a tunneler service.
- After installation, place an identity JWT file in `/opt/openziti/etc/identities/` and run `systemctl start ziti-edge-tunnel`.
- Updates are handled via system package manager (`apt update && apt upgrade`).

## Links

- [OpenZiti on GitHub](https://github.com/openziti/ziti)
- [Website](https://openziti.io)
