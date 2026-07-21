---
slug: paperclip
title: Paperclip
tags: [ai, automation, dev-tools]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/paperclip-ai.webp
by: fpulch
repo: https://github.com/paperclipai/paperclip
site: https://docs.paperclip.ing/
port: 3100
cpu: 4
ram: 8192
disk: 20
maintainer: fpulch
---

Paperclip is an open-source orchestration platform for managing autonomous AI agent teams with goals, routines, governance, and a browser-based control plane.

## Notes

Credentials and the initial CEO bootstrap invite are stored in `~/paperclip.creds`. Open the invite link to complete admin setup; generate a new one with `pnpm paperclipai auth bootstrap-ceo` from `/opt/paperclip-ai` after sourcing `.env`.

Codex and Claude Code are preinstalled. Authenticate them as root inside the container (`codex` / `claude /login`) so Paperclip can reuse the credentials.

When accessing from a different hostname, update `PAPERCLIP_PUBLIC_URL` in `/opt/paperclip-ai/.env`, restart the service, and run `pnpm paperclipai allowed-hostname <hostname>`.

## Links

- [Website](https://docs.paperclip.ing/)
- [GitHub](https://github.com/paperclipai/paperclip)
