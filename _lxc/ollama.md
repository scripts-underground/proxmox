---
slug: ollama
title: Ollama
tags: [ai]
logo: /assets/logos/ollama.webp
by: havardthom
co_author: [MickLesk]
repo: https://github.com/ollama/ollama
site: https://ollama.com
port: 80
cpu: 4
ram: 4096
disk: 40
maintainer: havardthom
---

Ollama allows you to run large language models locally.

## Notes

- Fresh installations expose the API at `http://<ip>`; the native CLI launcher
  supplies the local standard-port endpoint when `OLLAMA_HOST` is unset.
- Existing installations retain their configured binding, account, model home,
  keys and administrator service configuration during updates.
- Installation starts with an empty model store; no weights are downloaded.
- GPU passthrough is configured automatically when a GPU is detected on the host.
- Pull models with `ollama pull <model>` inside the container.

## Links

- [GitHub](https://github.com/ollama/ollama)
