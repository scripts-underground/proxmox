---
slug: nginxproxymanager
title: Nginx Proxy Manager
tags: [webservers-proxies]
logo: /assets/logos/nginxproxymanager.webp
by: tteck
repo: https://github.com/NginxProxyManager/nginx-proxy-manager
site: https://nginxproxymanager.com/
port: 81
cpu: 2
ram: 2048
disk: 8
maintainer: tteck
---

Nginx Proxy Manager is a tool that provides a web-based interface to manage Nginx reverse proxies. It enables users to easily and securely expose their services to the internet by providing features such as HTTPS encryption, domain mapping, and access control.

## Notes

- On first launch, a setup wizard will guide you through creating an admin account. There are no default credentials.
- You can install the specific one certbot you prefer, or you can Running /app/scripts/install-certbot-plugins within the Nginx Proxy Manager (NPM) LXC shell will install many common plugins.

## Links

- [Website](https://nginxproxymanager.com/)
- [GitHub](https://github.com/NginxProxyManager/nginx-proxy-manager)
