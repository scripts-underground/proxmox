---
slug: versitygw
title: VersityGW
tags: [s3, storage, gateway]
logo: /assets/logos/versitygw.webp
by: MickLesk
repo: https://github.com/versity/versitygw
site: https://github.com/versity/versitygw
port: 7070
cpu: 2
ram: 2048
disk: 8
maintainer: MickLesk
---

VersityGW is a high-performance S3-compatible gateway service that translates S3 API requests into backend storage operations. It supports POSIX filesystems, ScoutFS, Azure Blob Storage, and other S3 servers as backends.

## Notes

- Access the S3 Gateway at `http://<ip>:7070` and the WebUI at `http://<ip>:7071`
- Root access and secret keys are auto-generated and stored in `/etc/versitygw.d/gateway.conf`
- The WebUI (Beta) is enabled by default on port 7071
- Multiple gateway instances can run concurrently with unique config files in `/etc/versitygw.d/`

## Links

- [GitHub](https://github.com/versity/versitygw)
- [Wiki](https://github.com/versity/versitygw/wiki)
