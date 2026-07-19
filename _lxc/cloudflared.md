---
slug: cloudflared
title: Cloudflared
tags: [network, cloudflare]
logo: /assets/logos/cloudflared.webp
by: tteck
repo: https://github.com/cloudflare/cloudflared
site: https://www.cloudflare.com/
port: 0
cpu: 1
ram: 512
disk: 2
maintainer: tteck
---

Cloudflared connects your server to Cloudflare's global network, enabling secure tunnels, DNS-over-HTTPS, and other Cloudflare services without opening inbound ports.

## Notes

- Cloudflared is installed from Cloudflare's official package repository.
- The service can be configured for Cloudflare Tunnel, DNS-over-HTTPS (DoH), or other cloudflared features.
- Refer to the [Cloudflare documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) for tunnel setup.

## Links

- [Cloudflare](https://www.cloudflare.com/)
- [GitHub](https://github.com/cloudflare/cloudflared)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
