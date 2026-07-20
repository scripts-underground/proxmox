---
slug: localagi
title: LocalAGI
tags: [ai]
logo: /assets/logos/localagi.webp
by: BillyOutlast
repo: https://github.com/mudler/LocalAGI
site: https://github.com/mudler/LocalAGI
port: 3000
cpu: 2
ram: 4096
disk: 20
maintainer: alexindigo
---

LocalAGI is a self-hostable AI agent platform with a web UI, OpenAI-compatible APIs, and local-first model orchestration.

## Notes

- This script builds LocalAGI from source (Go + Bun) and runs it as a systemd service.
- LocalAGI runs in external-backend mode and does not provision local ROCm/NVIDIA runtimes.
- By default, LocalAGI is configured to call an OpenAI-compatible backend at `http://127.0.0.1:11434/v1` (Ollama-compatible) via `LOCALAGI_LLM_API_URL`.
- To use an external Ollama host, edit `/opt/localagi/.env` and set `LOCALAGI_LLM_API_URL=http://<ollama-host>:11434/v1`, then restart LocalAGI with `systemctl restart localagi`.

## Links

- [GitHub](https://github.com/mudler/LocalAGI)
