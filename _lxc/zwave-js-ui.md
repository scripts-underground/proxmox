---
slug: zwave-js-ui
title: Z-Wave JS UI
tags: [smarthome, zwave]
logo: /assets/logos/zwave-js-ui.webp
by: tteck
repo: https://github.com/zwave-js/zwave-js-ui
site: https://zwave-js.github.io/zwave-js-ui/
port: 8091
cpu: 2
ram: 1024
disk: 4
maintainer: tteck
---

Z-Wave JS UI is a full-featured Z-Wave control interface that integrates with Home Assistant and other home automation platforms. It provides a web-based interface for managing Z-Wave devices, network, and configuration.

## Notes

- Access the web UI at `http://{ip}:8091` to configure your Z-Wave controller.
- A Z-Wave USB stick (e.g., Zooz, Aeotec, GoControl) must be passed through to the container.
- The container stores persistent data in `/opt/zwave_store`.

## Links

- [Z-Wave JS UI on GitHub](https://github.com/zwave-js/zwave-js-ui)
- [Documentation](https://zwave-js.github.io/zwave-js-ui/)
