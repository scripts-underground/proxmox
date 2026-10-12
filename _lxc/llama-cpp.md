---
slug: llama-cpp
title: llama.cpp
tags: [ai]
logo: /assets/logos/llama-cpp.webp
by: CanbiZ
repo: https://github.com/ggml-org/llama.cpp
site: https://github.com/ggml-org/llama.cpp
port: 80
cpu: 4
ram: 4096
disk: 16
maintainer: alexindigo
---

Native llama.cpp HTTP API and Web UI, installed as an empty multi-model router.
Models load on demand; the native four-instance limit is configurable in
`/etc/llama-cpp.env`. Installation does not download model weights.

Place local GGUF files in `/var/lib/llama-cpp/models`, or configure native presets
in `/etc/llama-cpp-models.ini`. The cache lives in `/var/cache/llama-cpp`.
Binary updates preserve these locations, presets and service configuration.

The installer follows the binary build designated by upstream's stable release.
CPU, Vulkan and amd64 CUDA12.8 paths use coherent release artifacts; GPU usability
depends on mapped devices and matching userspace. No model is loaded at startup.
