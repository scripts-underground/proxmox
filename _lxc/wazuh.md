---
slug: wazuh
title: Wazuh
tags: [security, monitoring]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/wazuh.webp
by: Omar Minaya
repo: https://github.com/wazuh/wazuh
site: https://wazuh.com/
port: 443
cpu: 4
ram: 4096
disk: 25
maintainer: Omar Minaya
---

Open-source security monitoring solution that provides endpoint protection, network monitoring, and log analysis capabilities.

## Notes

- This script runs an external installer from https://wazuh.com/. The installer code is NOT maintained or audited by this repository.
- Default credentials are displayed during installation and saved to `~/wazuh.creds`. Run `cat ~/wazuh.creds` inside the container to view them.
- When running in an LXC container, `/dev/.lxc/*` paths are automatically excluded from rootcheck to prevent false positives.

## Links

- [Website](https://wazuh.com/)
- [GitHub](https://github.com/wazuh/wazuh)
- [Documentation](https://documentation.wazuh.com/)
