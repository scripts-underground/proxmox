---
slug: odysseus
title: Odysseus
tags: [ai, workspace, llm]
logo: /assets/logos/odysseus.svg
by: alexindigo
repo: https://github.com/pewdiepie-archdaemon/odysseus
site: https://pewdiepie-archdaemon.github.io/odysseus/
port: 80
cpu: 2
ram: 4096
disk: 8
maintainer: alexindigo
---

Odysseus is a self-hosted AI workspace with chat, agents, deep research, documents, email triage, calendar, and more.

## Notes

- Admin password is generated during setup and printed in the terminal. Change it after first login.
- Two usage scenarios: (1) Connect to a remote or separate LLM server — default 2 GB RAM works. (2) Run local LLM via Ollama — 16+ GB RAM recommended.
- tmux is installed for background model downloads.
- Configure LLM providers, search, and email inside Settings after first login.
- Uses SQLite by default. For production, configure an external PostgreSQL database.

## Links

- [Website](https://pewdiepie-archdaemon.github.io/odysseus/)
- [GitHub](https://github.com/pewdiepie-archdaemon/odysseus)
