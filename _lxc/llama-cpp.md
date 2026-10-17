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
Set `var_lxc_release` to pin a stable release, or `var_lxc_port` to override port 80.
`var_lxc_backend=auto` selects CUDA 12.8 on x64 NVIDIA, Vulkan on Intel/AMD,
and CPU otherwise. CPU and Vulkan support x64 and arm64. Explicit `cpu`, `vulkan`,
`cuda` and opt-in `sycl` backends are available; CUDA and SYCL require x64.
Intel's default stays Vulkan. SYCL uses the upstream FP16 binary with individual
oneAPI runtime libraries from Intel's apt repository, without the full toolkit.
GPU usability depends on mapped devices and matching userspace. No model is
loaded at startup.
