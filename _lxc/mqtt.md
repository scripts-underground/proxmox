---
slug: mqtt
title: MQTT
tags: [mqtt, iot, broker]
logo: /assets/logos/mqtt.webp
by: tteck (tteckster)
repo: https://github.com/eclipse/mosquitto
site: https://mosquitto.org/
port: 1883
cpu: 1
ram: 512
disk: 2
maintainer: tteck (tteckster)
---

Eclipse Mosquitto is an open-source message broker that implements the MQTT (Message Queuing Telemetry Transport) protocol. It is a lightweight and simple-to-use message broker that allows IoT devices and applications to communicate with each other by exchanging messages in real-time.

## Notes

- Default configuration disables anonymous access — create users with `mosquitto_passwd`
- Configuration file: `/etc/mosquitto/conf.d/default.conf`
- MQTT broker listens on port 1883 (no web UI)

## Links

- [GitHub](https://github.com/eclipse/mosquitto)
- [Website](https://mosquitto.org/)
- [Documentation](https://mosquitto.org/documentation/)
