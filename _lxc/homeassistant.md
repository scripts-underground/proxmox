---
slug: homeassistant
title: Home Assistant Container
tags: [iot-smart-home]
logo: /assets/logos/homeassistant.webp
by: tteck
repo: https://www.home-assistant.io/
site: https://www.home-assistant.io/
port: 8123
cpu: 2
ram: 2048
disk: 16
maintainer: tteck
---

A standalone container-based installation of Home Assistant Core means that the software is installed inside a Docker container, separate from the host operating system. This allows for flexibility and scalability, as well as improved security, as the container can be easily moved or isolated from other processes on the host.

## Notes

- Containerized version doesn't allow Home Assistant add-ons.
- If the LXC is created Privileged, the script will automatically set up USB passthrough.
- config path: `/var/lib/docker/volumes/hass_config/_data`
- Portainer interface: $IP: 9443 - User & password must be set manually within 5 minutes, otherwise a restart of Portainer is required!
- WARNING: Installation sources scripts outside of Community Scripts repo. Please check the source before installing.

## Links

- [Website](https://www.home-assistant.io/)
