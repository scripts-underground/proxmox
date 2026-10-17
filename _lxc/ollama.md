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

- Access the API at `http://<ip>`.
- GPU passthrough is configured automatically when a GPU is detected on the host.
- Pull models with `ollama pull <model>` inside the container.
- Installs from GitHub releases with an empty model store, running as the `ollama` user.
- Set `var_lxc_release` to pin a release and `var_lxc_port` to override port 80 at install time.
- Updates preserve the existing service, environment, port and models, including older installations on port 11434.

## Links

- [GitHub](https://github.com/ollama/ollama)
