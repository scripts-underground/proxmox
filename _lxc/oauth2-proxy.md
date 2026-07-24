---
slug: oauth2-proxy
title: OAuth2-Proxy
tags: [authentication, proxy]
logo: /assets/logos/oauth2-proxy.webp
by: bvdberg01
repo: https://github.com/oauth2-proxy/oauth2-proxy
site: https://oauth2-proxy.github.io/oauth2-proxy/
port: 4180
cpu: 1
ram: 512
disk: 3
maintainer: bvdberg01
---

A reverse proxy that provides authentication with Google, Azure, OpenID Connect and many more identity providers.

## Notes

- This application includes a blank configuration file by default due to the wide range of available configuration options. Refer to the [official documentation](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview) for guidance.
- After changing the config, restart OAuth2-Proxy with: `systemctl restart oauth2-proxy`
- Config file location: `/opt/oauth2-proxy/config.toml`

## Links

- [Website](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Documentation](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview)
- [GitHub](https://github.com/oauth2-proxy/oauth2-proxy)
