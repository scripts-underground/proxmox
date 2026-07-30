---
slug: warracker
title: Warracker
tags: [warranty]
logo: /assets/logos/warracker.webp
by: BvdBerg01
repo: https://github.com/sassanix/Warracker
site: https://warracker.com
port: 80
cpu: 1
ram: 512
disk: 4
maintainer: BvdBerg01
---

Open source, self-hostable warranty tracker to monitor expirations, store receipts, and files. You own the data, your rules!

## Notes

- Access the web UI at `http://<ip>` to get started.
- Database credentials are stored in `/root/warracker.creds` inside the container.
- The app uses PostgreSQL for data storage and Nginx as a reverse proxy.

## Links

- [Website](https://warracker.com)
- [GitHub](https://github.com/sassanix/Warracker)
