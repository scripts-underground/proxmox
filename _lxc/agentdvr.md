---
slug: agentdvr
title: AgentDVR
tags: [dvr]
logo: /assets/logos/agentdvr.webp
by: tteck
repo: https://github.com/ispysoftware/agent
site: https://www.ispyconnect.com/
port: 8090
cpu: 2
ram: 2048
disk: 8
maintainer: tteck
---

AgentDVR is a cross-platform video surveillance application from iSpyConnect that supports ONVIF, RTSP, and USB cameras. It features motion detection, recording, live viewing, and cloud backup capabilities.

## Notes

- Access the web UI at `http://{ip}:8090` to complete the initial setup.
- GPU hardware acceleration is enabled by default for supported devices.
- The application checks for updates on each script run and applies them automatically.
- Configuration is stored under `/opt/agentdvr/agent/`.

## Links

- [GitHub](https://github.com/ispysoftware/agent)
- [Website](https://www.ispyconnect.com/)
- [Forums](https://www.ispyconnect.com/forum)
