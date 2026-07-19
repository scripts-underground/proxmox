---
slug: asterisk
title: Asterisk
tags: [telephone, pbx]
logo: https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/asterisk.webp
by: michelroegl-brunner
repo: https://github.com/asterisk/asterisk
site: https://asterisk.org
port: 5060
cpu: 2
ram: 2048
disk: 4
maintainer: michelroegl-brunner
---

Open-source PBX and telephony platform. Provides VoIP, SIP trunking, IVR, voicemail, conferencing, and call routing for building custom phone systems.

## Notes

- Asterisk does not have a web UI by default. Use `asterisk -r` from the container CLI to manage the PBX.
- SIP endpoints connect on UDP/TCP port 5060.
- Configuration files are in `/etc/asterisk/`.
- Built from source — updates require rebuilding.

## Links

- [Website](https://asterisk.org)
- [GitHub](https://github.com/asterisk/asterisk)
