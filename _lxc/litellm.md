---
slug: litellm
title: LiteLLM
tags: [ai, interface]
logo: /assets/logos/litellm.webp
by: stout01
repo: https://github.com/BerriAI/litellm
site: https://litellm.ai/
port: 4000
cpu: 2
ram: 2048
disk: 4
maintainer: stout01
---

AI proxy server to call 100+ LLMs using the OpenAI format. Supports authentication, cost tracking, and rate limiting.

## Notes

- Default master key is `sk-1234` — change it in `/opt/litellm/litellm.yaml`.
- Uses PostgreSQL for persistent storage of models and configuration.

## Links

- [Website](https://litellm.ai/)
- [GitHub](https://github.com/BerriAI/litellm)
