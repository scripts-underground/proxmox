---
slug: crowdsec
title: CrowdSec
tags: [auth-security, network]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/crowdsec.webp
by: tteck
repo: https://github.com/crowdsecurity/crowdsec
site: https://crowdsec.net
port: 8080
maintainer: tteck
---

CrowdSec is an open-source, crowdsourced security engine that detects and blocks malicious IPs. It analyzes logs, enriches signals with community threat intelligence, and enforces decisions through bouncers — this addon installs the CrowdSec agent together with the iptables firewall bouncer.

## Notes

- Runs inside an existing LXC container (Debian/Ubuntu only) — must NOT run on the Proxmox VE host
- Exposes the Local API on port 8080 (used by `cscli` and remote bouncers; no web UI)
- Update with: `update-crowdsec` — Uninstall with: `uninstall-crowdsec`
- Re-running the installer offers update/uninstall via the framework guard

## Links

- [Website](https://crowdsec.net)
- [GitHub](https://github.com/crowdsecurity/crowdsec)
