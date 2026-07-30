---
slug: ps5-mqtt
title: PS5-MQTT
tags: [smarthome, automation]
logo: /assets/logos/ps5-mqtt.webp
by: liecno
repo: https://github.com/FunkeyFlo/ps5-mqtt
site: https://github.com/FunkeyFlo/ps5-mqtt
port: 8645
cpu: 1
ram: 512
disk: 3
maintainer: liecno
---

Integrate your Sony Playstation 5 devices with Home Assistant using MQTT. Supports power/wake/standby control, local network device discovery, and a web UI for acquiring credentials.

## Notes

- Requires an MQTT broker (e.g. Mosquitto) — configure `config.json` at `/opt/.config/ps5-mqtt/config.json` with your MQTT credentials before starting.
- Use the web UI at `http://{ip}:8645` to authenticate with each PlayStation device.
- Ensure all required remote play features are enabled on your PS5 (Settings > System > Remote Play > Enable Remote Play).

## Links

- [PS5-MQTT on GitHub](https://github.com/FunkeyFlo/ps5-mqtt)
- [PS5-MQTT Documentation](https://github.com/FunkeyFlo/ps5-mqtt/tree/main/add-ons/ps5-mqtt)
