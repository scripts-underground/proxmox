---
slug: jitsi-meet
title: Jitsi-Meet
tags: [video, conference, communication]
logo: /assets/logos/jitsi-meet.webp
by: MickLesk
repo: https://github.com/jitsi/jitsi-meet
site: https://jitsi.org/
port: 443
cpu: 4
ram: 4096
disk: 12
maintainer: MickLesk
---

Secure, Simple and Scalable Video Conferences that you use as a standalone app or embed in your web application.

## Notes

- Access the web UI at `https://<ip>` to start or join meetings.
- A self-signed certificate is generated during installation.
- Installed via the official Jitsi apt repository (debian packages).
- Updates are handled via `apt update && apt install --only-upgrade`.
- Jitsi Meet runs on port 443 (HTTPS) by default.

## Links

- [Website](https://jitsi.org/)
- [GitHub](https://github.com/jitsi/jitsi-meet)
