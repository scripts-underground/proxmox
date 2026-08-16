---
slug: coder-code-server
title: Code Server
tags: [ai-dev]
logo: /assets/logos/coder-code-server.webp
by: tteck
repo: https://github.com/coder/code-server
site: https://coder.com
port: 8680
maintainer: tteck
---

code-server runs VS Code on a remote server, accessible through the browser. Develop from any device against a consistent environment powered by the container it runs in, with full access to the VS Code extension ecosystem.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Update with: `update-coder-code-server` — Uninstall with: `uninstall-coder-code-server`
- Re-running the installer offers update/uninstall via the framework guard
- Runs as the templated systemd service `code-server@root`; config at `~/.config/code-server/config.yaml`
- Default config binds `0.0.0.0:8680` with `auth: none` — to require a password, set `auth: password` and a `password:` hash in the config file, then `systemctl restart code-server@root`
- An existing `config.yaml` is never overwritten on install or update

## Links

- [Website](https://coder.com)
- [GitHub](https://github.com/coder/code-server)
