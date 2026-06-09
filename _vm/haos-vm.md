---
slug: haos-vm
title: Home Assistant OS
tags: [iot-smart-home]
logo: /assets/logos/haos-vm.webp
by: tteck
repo: https://www.home-assistant.io/
site: https://www.home-assistant.io/
port: 8123
cpu: 2
ram: 4096
disk: 32
maintainer: tteck
---

This script automates the process of creating a Virtual Machine (VM) using the official KVM (qcow2) disk image provided by the Home Assistant Team. It involves finding, downloading, and extracting the image, defining user-defined settings, importing and attaching the disk, setting the boot order, and starting the VM.

## Notes

- The disk must have a minimum size of 32GB and its size cannot be changed during the creation of the VM.
- After the script completes, click on the VM, then on the Summary or Console tab to find the VM IP.

## Links

- [Website](https://www.home-assistant.io/)
