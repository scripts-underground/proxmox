---
slug: rabbitmq
title: RabbitMQ
tags: [mqtt]
logo: /assets/logos/rabbitmq.webp
by: tteck
co_author: [MickLesk]
repo: https://github.com/rabbitmq/rabbitmq-server
site: https://www.rabbitmq.com/
port: 15672
cpu: 1
ram: 1024
disk: 4
maintainer: tteck
---

RabbitMQ is a reliable and mature open-source message broker that implements the AMQP 0-9-1, AMQP 1.0, MQTT, and STOMP protocols for distributed messaging and queue-based workloads.

## Notes

- The Management UI is available at port 15672 with credentials `proxmox` / `proxmox`.
- The default AMQP port is 5672.
- Configuration lives in `/etc/rabbitmq/`.

## Links

- [Website](https://www.rabbitmq.com/)
- [GitHub](https://github.com/rabbitmq/rabbitmq-server)
