---
slug: colanode
title: Colanode
tags: [collaboration, notes, chat]
logo: /assets/logos/colanode.webp
by: MickLesk
repo: https://github.com/colanode/colanode
site: https://colanode.com/
port: 4000
cpu: 4
ram: 4096
disk: 16
maintainer: MickLesk
---

Open-source, local-first collaboration workspace — a self-hosted Slack and Notion alternative with real-time chat, rich text pages, customizable databases, and file management.

## Notes

- Before using the app: download and import the self-signed certificate into your browser. Navigate to https://YOUR_IP:4000/colanode.crt and install it as a trusted CA. This is required for Service Worker and OPFS storage to work.
- Access the web interface at https://YOUR_IP:4000. When adding a server in the desktop or mobile app, enter https://YOUR_IP:4000 as the server URL.
- No default credentials — open the web UI and register a new account on first access.
- Requires at least 4 GB RAM for the build process.

## Links

- [Website](https://colanode.com/)
- [GitHub](https://github.com/colanode/colanode)
- [Documentation](https://github.com/colanode/colanode/blob/main/hosting/docker)
