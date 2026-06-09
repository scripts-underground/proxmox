---
slug: nomad
title: Project N.O.M.A.D.
tags: [offline, knowledge, education, ai]
logo: /assets/logos/nomad.webp
by: alexindigo
repo: https://github.com/Crosstalk-Solutions/project-nomad
site: https://www.projectnomad.us
port: 80
cpu: 4
ram: 4096
disk: 16
image: debian-13
maintainer: alexindigo
---

Node for Offline Media, Archives, and Data.

A self-contained offline-first knowledge server. It bundles several open-source tools into a single Docker Compose stack — offline Wikipedia (Kiwix), Khan Academy courses (Kolibri), AI chat (Ollama), offline maps (ProtoMaps), notes (Flatnotes), and more.

Run the install script, download the content you want while online, and it keeps working without internet, forever.

## Requirements

- **Disk**: 16 GB minimum, 250 GB+ recommended if downloading AI models or large Wikipedia dumps
- **RAM**: 4 GB minimum, 32 GB+ recommended for running local LLMs
- **GPU**: NVIDIA GPU recommended for AI acceleration (passthrough configured automatically)
- **Architecture**: x86_64 only (arm64 is not supported upstream)

## Notes

- Has no built-in authentication. Use network-level controls to manage access.
- AI Assistant is optional — skip it during setup if not needed.
- All data persists in `/opt/project-nomad/` (bind mounts, easy to back up).
- Default install uses port 80 (configurable via `var_port`).

## Links

- [Website](https://www.projectnomad.us)
- [Installation Guide](https://www.projectnomad.us/install)
- [Hardware Guide](https://www.projectnomad.us/hardware)
- [FAQ](https://github.com/Crosstalk-Solutions/project-nomad/blob/main/FAQ.md)
- [Benchmark Leaderboard](https://benchmark.projectnomad.us)
