---
slug: zigbee2mqtt
title: Zigbee2MQTT
tags: [smarthome, zigbee, mqtt]
logo: /assets/logos/zigbee2mqtt.webp
by: tteck
repo: https://github.com/Koenkk/zigbee2mqtt
site: https://www.zigbee2mqtt.io/
port: 9442
cpu: 2
ram: 1024
disk: 5
maintainer: tteck
---

Zigbee2MQTT bridges Zigbee devices to MQTT, allowing you to control your Zigbee devices via MQTT.

## Notes

- Requires a Zigbee coordinator (USB dongle).
- The container must be **privileged** for USB/serial access (`var_unprivileged=0`).
- Access the web UI at `http://{ip}:9442` to complete setup.

## Links

- [GitHub](https://github.com/Koenkk/zigbee2mqtt)
- [Website](https://www.zigbee2mqtt.io/)
