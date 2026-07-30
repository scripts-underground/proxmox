---
slug: fileflows
title: FileFlows
tags: [media, automation]
logo: /assets/logos/fileflows.webp
by: kkroboth
repo: https://github.com/revenz/FileFlows
site: https://fileflows.com
port: 19200
cpu: 2
ram: 2048
disk: 8
maintainer: kkroboth
---

File processing application that can execute actions against a file in a tree flow structure.

FileFlows lets you design, schedule, and run automated file processing pipelines — from a single server to a distributed cluster. Supports video transcoding, audio processing, images, ebooks, comics, and more with hardware acceleration (Intel QSV, NVIDIA NVENC, AMD AMF, VAAPI).

## Notes

- Access the web UI at `http://{ip}:19200` to configure flows
- FFmpeg is required for video processing — install it and add the path under Variables in the web console
- Data directory is at `/opt/fileflows/Data`

## Links

- [GitHub](https://github.com/revenz/FileFlows)
- [Documentation](https://fileflows.com/docs)
