---
slug: protonmail-bridge
title: Proton Mail Bridge
tags: [mail, proton]
logo: /assets/logos/protonmail-bridge.webp
by: steveonjava
repo: https://github.com/ProtonMail/proton-bridge
site: https://proton.me/mail/bridge
port: 143
cpu: 2
ram: 1024
disk: 8
maintainer: steveonjava
---

Proton Mail Bridge runs a local IMAP/SMTP service that lets traditional mail clients access a Proton mailbox. This LXC runs Bridge headless and forwards IMAP/SMTP to the LAN using systemd socket activation (systemd-socket-proxyd).

## Notes

- After install, run `protonmailbridge-configure` inside the container for first-time setup.
- LAN forwarding (container IP): IMAP 143 -> 127.0.0.1:1143, SMTP 587 -> 127.0.0.1:1025.
- You can later use `protonmailbridge-configure` to temporarily stop the service and enter the Bridge CLI.
- Updates are handled via this script.

## Links

- [GitHub](https://github.com/ProtonMail/proton-bridge)
- [Website](https://proton.me/mail/bridge)
- [Documentation](https://proton.me/support/bridge-cli-guide)
