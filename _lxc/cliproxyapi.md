---
slug: cliproxyapi
title: CLIProxyAPI
tags: [ai]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/openai.webp
by: mathiasnagler
repo: https://github.com/router-for-me/CLIProxyAPI
site: https://github.com/router-for-me/CLIProxyAPI
port: 8317
cpu: 1
ram: 512
disk: 2
maintainer: mathiasnagler
---

CLIProxyAPI is a proxy server that provides OpenAI-compatible API endpoints for multiple AI CLI tools including Claude Code, Gemini CLI, OpenAI Codex, and more. It enables leveraging free-tier AI subscriptions through a unified API with features like credential routing, quota management, and request retrying.

## Notes

- Generated credentials (API Key, Management Password) are stored in `/opt/cliproxyapi/config.yaml` inside the LXC.
- After setup, authenticate your AI providers via the built-in management panel at port 8317.

## Links

- [GitHub](https://github.com/router-for-me/CLIProxyAPI)
- [Documentation](https://help.router-for.me/)
