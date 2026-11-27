---
slug: rea
title: REA
tags: [reverse-engineering, tools]
logo: /assets/logos/rea.webp
by: alexindigo
repo: https://github.com/morluto/rea
site: https://github.com/morluto/rea
port: 22
cpu: 2
ram: 4096
disk: 64
maintainer: alexindigo
---

Reverse Engineer Anything (REA) provides a CLI and stdio MCP server for file analysis. This Debian 13 amd64 container builds REA 6.4.0 from pinned source and includes OpenJDK 21, Node.js 24.18.0, npm 11.16.0, Ghidra 12.1.4, jadx-headless-mcp 0.7.1, and Apktool 3.0.3. It does not install proprietary engines, the Frida native binding, or other full-workbench extras.

## How it works

```text
Your computer                   Proxmox host / Debian 13 LXC
+--------------------------+    +----------------------------------------------------+
| Your MCP client          |    | SSH server :22                                     |
| (SSH host key pinned)    |    |   | runs as user "rea"                             |
|                          |    |   v                                                |
| Sends tool requests      |--->| /srv/rea/bin/rea mcp                               |
| Receives tool results    |<---|   | loads defaults + /srv/rea/environment.sh       |
|                          |    |   v                                                |
| JSON-RPC over SSH stdio  |    | Node.js / REA MCP server                           |
+--------------------------+    |   |                                                |
                                |   +-- Native binary requests                       |
                                |   |     v                                          |
                                |   |   Ghidra headless (Java 21, 1G heap)           |
                                |   |     +-- Native decompiler                      |
                                |   |                                                |
                                |   +-- Android method requests                      |
                                |   |     v                                          |
                                |   |   jadx-headless-mcp (Java, 1024 MiB heap)      |
                                |   |                                                |
                                |   +-- APK manifest / resource requests             |
                                |         v                                          |
                                |       /srv/rea/bin/apktool -> Apktool              |
                                |                                                    |
                                | Files: /srv/rea/jobs  (inputs and outputs)         |
                                |        /srv/rea/tmp   (scratch space)              |
                                |        /srv/rea/cache (caches)                     |
                                +----------------------------------------------------+
```

REA starts and manages the analysis engines; requests and results travel over the same SSH connection. Copy input files into the container before requesting analysis. The heap sizes shown are defaults, configurable in `/srv/rea/environment.sh`.

## Access

The `rea` account has no sudo access and no usable password. As root inside the container, add your own public key to `/home/rea/.ssh/authorized_keys`; give `rea` ownership and set mode `0600`. The `.ssh` directory is created with mode `0700`. Verify the SSH host key fingerprint from the container console (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) and pin the corresponding key on the client before connecting.

Use this stdio MCP command, replacing `<container-address>` with your container's address:

```sh
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes rea@<container-address> /srv/rea/bin/rea mcp
```

There is no web UI or HTTP MCP endpoint. Copy inputs to `/srv/rea/jobs/` and pass container-local paths to REA. Temporary files and caches use `/srv/rea/tmp/` and `/srv/rea/cache/`. Java heap settings are in `/srv/rea/environment.sh`; raise the container memory before increasing them for larger jobs.

Run `update` as root to check the installed pins, or `update --clean` to rebuild the same stack. Updates preserve jobs, environment settings and SSH keys. Previous runtime releases are kept under `/srv/rea/releases/` for active sessions; they can be removed after those sessions end. Do not remove the release referenced by `/srv/rea/current`.

This container is not a sandbox. Do not execute unknown or untrusted samples in it.
