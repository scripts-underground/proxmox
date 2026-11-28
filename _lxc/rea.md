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

## Setup and access

Interactive installation adds two stages after the usual container settings:

1. **Access method:** choose an SSH key, a password, or both. Both lets you sign in with either method; it is not two-factor authentication. Choose key or both for unattended MCP. Password-only access is for interactive SSH clients.
2. **Credentials:** depending on the method, select a public key, enter and confirm a separate REA password, or do both. If you selected keys for root, you can explicitly reuse those public keys for REA. Private keys stay on your client or in its SSH agent. The `rea` account has no sudo access, and its login is separate from root SSH and the container console.

Noninteractive installs without explicit access inputs leave REA SSH access pending. As root in the container, run `configure-ssh-access rea` in a terminal to finish setup or change it later. If an existing install does not have that command, run the current installer source inside the container as root to install it without changing authentication or rebuilding REA:

```sh
rea_source=$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/scripts/lxc/rea.sh) &&
  PHS_SILENT=1 REA_INSTALL_SSH_SETUP=1 bash -c "$rea_source" &&
  configure-ssh-access rea
```

Before connecting, verify the SSH host key fingerprint from the container console (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`). Pin the matching public host key in your client's `known_hosts` for the address you use. Replace `rea.example.net` below with your container's address. For a manual CLI session:

```sh
ssh -o StrictHostKeyChecking=yes rea@rea.example.net
# Then, inside the SSH session:
/srv/rea/bin/rea --help
```

For a key-enabled account, use this stdio MCP command with the key available from your local SSH configuration or agent:

```sh
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes rea@rea.example.net /srv/rea/bin/rea mcp
```

There is no web UI or HTTP MCP endpoint. Copy inputs to `/srv/rea/jobs/` and pass container-local paths to REA. Temporary files and caches use `/srv/rea/tmp/` and `/srv/rea/cache/`. Java heap settings are in `/srv/rea/environment.sh`; raise the container memory before increasing them for larger jobs.

Run `update` as root to check the installed pins, or `update --clean` to rebuild the same stack. Updates preserve jobs, environment settings, SSH credentials, and operator keys. They do not run SSH setup. Previous runtime releases are kept under `/srv/rea/releases/` for active sessions; they can be removed after those sessions end. Do not remove the release referenced by `/srv/rea/current`.

This container is not a sandbox. Do not execute unknown or untrusted samples in it.
