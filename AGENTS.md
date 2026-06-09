# Contributing to scripts-underground

## Script Architecture

Every script is **single-file** — the container template, install logic, and update logic live in one file. There are no separate install scripts.

### LXC Script (`scripts/lxc/appname.sh`)

```bash
#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: YourName (GitHubUsername)
# License: MIT | https://github.com/scripts-underground/proxmox/raw/main/LICENSE
# Source: https://application-url.com

APP="AppName"
var_tags="${var_tags:-tag1;tag2}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt install -y dep1 dep2
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

  msg_info "Creating Service"
  cat <<'SVCEOF' >/etc/systemd/system/appname.service
[Unit]
Description=AppName Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=/opt/appname/bin/server
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl enable -q --now appname
  msg_ok "Created Service"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/appname ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "appname" "owner/repo"; then
    msg_info "Stopping Service"
    systemctl stop appname
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"
    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
```

### Required Functions

| Function | Where | Purpose |
|---|---|---|
| `install_script()` | Container | App installation (apt, git, systemd) |
| `update_script()` | Container | App update logic |

### Optional Hooks

| Hook | Where | Purpose |
|---|---|---|
| `pre_build_script()` | Host | Pre-flight validation |
| `post_build_script()` | Host | Post-creation tweaks (`pct set`, etc.) |
| `post_install_script()` | Host | Success messages with access URLs |

All hooks run on the **host** except `install_script()` and `update_script()` which run inside the container. The bootstrap (`misc/bootstrap/lxc`) validates, initializes, and orchestrates the pipeline — the contributor only supplies data and functions.

### Metadata (`_lxc/appname.md`)

```yaml
---
slug: appname
title: AppName
tags: [tag1, tag2]
logo: /assets/logos/appname.webp
by: YourGitHubUsername
repo: https://github.com/owner/repo
site: https://appname.com
cpu: 2
ram: 2048
disk: 8
port: 3000
maintainer: YourGitHubUsername
---

Short description.

## Notes

- Setup notes
- Compatibility info

## Links

- [Website](https://appname.com)
```

---

## Adding a New LXC Script

1. Run `cp scripts/lxc/_template.sh scripts/lxc/yourapp.sh`  
   (If no template exists, copy an existing simple script like `kiwix.sh`)

2. Fill in the metadata at the top: `APP`, `var_tags`, `var_cpu`, `var_ram`, `var_disk`, `var_os`, `var_version`

3. Write `install_script()` — this is the app install logic that runs inside the container. Start with the standard init block (`color; verb_ip6; catch_errors; setting_up_container; network_check; update_os`). Do NOT include `motd_ssh`, `customize`, or `cleanup_lxc` — the bootstrap handles them.

4. Write `update_script()` — this is the app update logic. Must start with `header_info; check_container_storage; check_container_resources` and end with `exit`.

5. Write `post_install_script()` — success message with access URL.

6. Create `_lxc/yourapp.md` with YAML front matter (see template above).

7. Add a logo to `assets/logos/` or reference a URL/base64 SVG in the metadata.

8. Source the bootstrap at the very bottom: `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")`

9. Never call `start`, `build_container`, or `description` — the bootstrap handles the flow.

10. Test with `REPO_BASE=... bash scripts/lxc/yourapp.sh`

---

## Other Script Types

### VM Scripts (`scripts/vm/appname.sh`)

Self-contained scripts that create VMs. Source `api.func`, handle `qm create`, and source `bootstrap/vm` at the bottom.

### Addon Scripts (`scripts/addon/appname.sh`)

Run inside existing LXC containers. Source `core.func` + `tools.func`, install additional tools, source `bootstrap/addon` at the bottom.

### PVE Scripts (`scripts/pve/toolname.sh`)

Run on the Proxmox host. Source `core.func` + `api.func`, perform host-level operations, source `bootstrap/pve` at the bottom.

---

## Conventions

- **No `start`/`build_container`/`description` calls** in LXC scripts — the bootstrap runs them
- **No `motd_ssh`/`customize`/`cleanup_lxc`** in `install_script()` — the wrapper handles them
- **No host-level execution** — all install commands go inside `install_script()` (container-side)
- **Credentials stay inside container** — write to files, reference paths in `post_install_script()`
- **Use `$STD`** before all apt/npm/build commands
- **Use `fetch_and_deploy_gh_release`** instead of curl/wget
- **Use `setup_*` functions** for runtimes (nodejs, postgresql, go, rust, python/uv)
- **Never use Docker** — bare-metal installation only
- **Never use `sudo`** — scripts run as root inside containers
- **Use `apt`** not `apt-get`

## Site

- **Jekyll** site in `assets/`, `_layouts/`, `_includes/`
- Semantic colors: `--cta` (orange, clickable), `--accent` (green, decorative), `--text-muted` (pills)
- `_plugins/external_links.rb` sanitizes markdown and adds `rel="noopener noreferrer"` to links
- `fetch-logos.rb` converts remote logos to WebP 512x512
