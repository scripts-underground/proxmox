---
slug: ollama
title: Ollama
tags: [ai]
logo: /assets/logos/ollama.webp
by: havardthom
co_author: [MickLesk]
repo: https://github.com/ollama/ollama
site: https://ollama.com
port: 11434
cpu: 4
ram: 4096
disk: 40
maintainer: havardthom
---

Ollama allows you to run large language models locally.

## Notes

- Access the API at `http://{ip}:11434`
- GPU passthrough is configured automatically when a GPU is detected on the host.
- Pull models with `ollama pull <model>` inside the container.

## Links

- [GitHub](https://github.com/ollama/ollama)
