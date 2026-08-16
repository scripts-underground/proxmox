---
slug: pyenv
title: pyenv
tags: [ai-dev]
logo: /assets/logos/pyenv.webp
by: tteck
repo: https://github.com/pyenv/pyenv
site: https://github.com/pyenv/pyenv
maintainer: tteck
---

pyenv lets you easily switch between multiple versions of Python. It intercepts Python commands using shim executables, so the active Python version can change per user or per project without touching the system interpreter. This addon installs the latest Python 3.14 via pyenv and optionally offers Home Assistant, ESPHome, and Matter Server payloads during setup.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only)
- Restart your shell after installation (or run `exec $SHELL`) to activate pyenv
- Optional payloads during install: Home Assistant (port 8123), ESPHome Dashboard (port 6052), Matter Server
- Update with: `update-pyenv` — Uninstall with: `uninstall-pyenv`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://pyenv.run/)
- [GitHub](https://github.com/pyenv/pyenv)
