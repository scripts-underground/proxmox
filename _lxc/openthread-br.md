---
slug: openthread-br
title: OpenThread Border Router
tags: [thread, iot, border-router, matter]
logo: /assets/logos/openthread-br.webp
by: MickLesk
co_author: [tomfrenzel]
repo: https://github.com/openthread/ot-br-posix
site: https://openthread.io/guides/border-router
port: 80
cpu: 2
ram: 2048
disk: 4
maintainer: MickLesk
---
OpenThread Border Router (OTBR) connects a Thread network to other IP-based networks such as Wi-Fi or Ethernet, providing bidirectional connectivity, mDNS/SRP service discovery, NAT64, and external Thread commissioning.

## Notes

- Services are enabled but not started at install. Configure `/etc/default/otbr-agent` with your RCP device, then run: `systemctl restart otbr-agent otbr-web`
- Home Assistant: Add 'OpenThread Border Router' integration with URL `http://{IP}:8081`. Web UI is on port 80.
- Requires a Thread Radio Co-Processor (RCP) device. USB: pass through to LXC (e.g. `/dev/ttyACM0`). TCP: use socat forkpty pattern (see `/etc/default/otbr-agent` for examples).
- Container must be **privileged** for network configuration and TUN device access.

## Links

- [Website](https://openthread.io/)
- [GitHub](https://github.com/openthread/ot-br-posix)
- [Documentation](https://openthread.io/guides/border-router)
