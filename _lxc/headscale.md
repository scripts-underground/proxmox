---
slug: headscale
title: Headscale
tags: [networking, vpn]
logo: /assets/logos/headscale.webp
by: tteck (tteckster)
repo: https://github.com/juanfont/headscale
site: https://headscale.net
port: 8080
cpu: 1
ram: 512
disk: 2
maintainer: tteck (tteckster)
---

Open source, self-hosted implementation of the Tailscale control server.

Headscale implements the Tailscale control server protocol, enabling you to run your own VPN coordination plane without relying on Tailscale's SaaS. It manages node registration, key exchange, ACL enforcement, DERP relay routing, and DNS configuration — all from your own infrastructure.

## Notes

- Access the Headscale API at `http://<ip>:8080`
- headscale-admin UI available at `http://<ip>/admin` (requires Caddy or reverse proxy configuration)
- The `headscale` CLI is available inside the container for administration

## Links

- [GitHub](https://github.com/juanfont/headscale)
- [Documentation](https://headscale.net)
