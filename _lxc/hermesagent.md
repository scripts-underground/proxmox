---
slug: hermesagent
title: Hermes Agent
tags: [ai, automation, agent]
logo: /assets/logos/hermesagent.webp
by: steveonjava
repo: https://github.com/NousResearch/hermes-agent
site: https://hermes-agent.nousresearch.com
port: 8642
cpu: 2
ram: 4096
disk: 20
maintainer: steveonjava
---
Self-improving AI agent by Nous Research. Connects to 15+ LLM providers, executes terminal commands, browses the web, and learns from experience. Supports 16 messaging platforms (Telegram, Discord, Slack, WhatsApp, Signal, Matrix, and more) with persistent memory and autonomous skill creation.
## Notes
- After container startup, login, switch to the hermes user (`su - hermes`) and run `hermes setup` to configure your model provider and gateway server.
- OpenAI-compatible API server available at `http://{ip}:8642/v1`. API key is stored in `/home/hermes/.hermes/.env`.
- Access the web dashboard via SSH tunnel: `ssh -fNL 9119:localhost:9119 root@{ip}`, then open http://localhost:9119
- Installation sources scripts outside of Community Scripts repo. Please check the source before installing.
- Hermes can execute terminal commands. The agent runs as a dedicated 'hermes' service user for isolation.
## Links
- [Website](https://hermes-agent.nousresearch.com/)
- [GitHub](https://github.com/NousResearch/hermes-agent)
