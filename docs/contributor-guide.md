# Contributor guide — LXC scripts

> Audience: script authors and AI agents writing LXC scripts for this repo.
> Replaces the "Script Architecture" section of the old `AGENTS.md`.

## Overview

An LXC script is a single bash file at `scripts/lxc/<slug>.sh`. It declares
configuration variables and hook functions. The repo provides a framework
(`misc/build.func`, `misc/install.func`, `misc/tools.func`, etc.) that the
script pulls in via one line at the bottom.

The script author defines **what** (install steps) and **where** (resource
defaults). The framework handles **when** (orchestration) and **how**
(container creation, template download, error handling).

## Minimal LXC script template

```bash
#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: YourName (GitHubUsername)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
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
  msg_info "Installing Dependencies"
  $STD apt install -y dep1 dep2
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "appname" "owner/repo" "tarball" "latest" "/opt/appname"

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/appname.service
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
EOF
  systemctl enable -q --now appname
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  # check_and_release_lock, stop services, fetch_and_deploy_* for new version, restart
  exit
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
```

## File structure (required order)

```
1.  #!/usr/bin/env bash
2.  REPO_BASE="${REPO_BASE:-<upstream-url>}"
3.  Copyright header (Copyright, Author, License, Source)
4.  APP="Name"
5.  var_* defaults (cpu, ram, disk, os, version, tags, unprivileged)
6.  Private helper variables (optional: DEFAULT_PORT, SRC_URL, SERVICE_PATH, etc.)
7.  install_script()      ← required
8.  post_build_script()   ← optional, host-side after container creation
9.  post_install_script() ← optional host hook, success messages with URLs
10. update_script()       ← optional in-container update
11. uninstall_script()    ← optional in-container removal
12. source <(curl ... bootstrap/lxc)   ← last line
```

## What the bootstrap provides

At the bottom of your script, the bootstrap line sources the framework.
Once it runs, your hook functions are called in this order:

0. `header_info()` — **optional**. Custom ASCII art displayed early in
   the bootstrap (after colors, before error traps). If you don't define
   it, the framework shows a generic header. Define it if your upstream
   script has artwork worth preserving.
1. `install_script()` — runs INSIDE the container. App-specific install.
2. `post_build_script()` — runs ON THE HOST after container creation.
   Use for `pct set` commands, volume mounts, firewall rules.
3. `post_install_script()` — runs ON THE HOST after everything completes.
   Print access URLs and credentials here. `$IP` is available.
4. `update_script()` — runs INSIDE the container via a persistent bundle
   at `/usr/local/sbin/update`. User runs `update` to trigger upgrades.
5. `uninstall_script()` — runs INSIDE the container via a bundle at
   `/usr/local/sbin/uninstall` (self-destructs on success).

## What you should NOT call

The bootstrap handles orchestration. Your script should NEVER call:
- `start`, `build_container`, `complete_install`
- `variables`, `color`, `catch_errors`
- `motd_ssh`, `customize`, `cleanup_lxc` — `build_container` handles these.

## Variables available to your `install_script()`

Declared by your script:
- `$APP`, `$var_cpu`, `$var_ram`, `$var_disk`, `$var_os`, `$var_version`

Set by the framework and available inside the container:
- `$IP`, `$CTID`, `$NSAPP`, `$REPO_BASE`
- `$PASSWORD` (the root password chosen during install)

## Helpers available inside the container

From `core.func` (always available):
- `msg_info`, `msg_ok`, `msg_error`, `msg_warn`, `msg_custom`
- `$STD` — prefix commands with `$STD` to suppress output when not verbose
- `exit_script`
- `cleanup_lxc`

From `install.func` (always available):
- `pkg_update`, `pkg_upgrade`, `pkg_install`, `pkg_remove`, `pkg_clean`
- `svc_enable`, `svc_disable`, `svc_start`, `svc_stop`, `svc_restart`

From `tools.func` (available after `update_os` runs in the wrapper):
- `fetch_and_deploy_gh_release`, `fetch_and_deploy_codeberg_release`,
  `fetch_and_deploy_gl_release`, `fetch_and_deploy_from_url`
- `setup_nodejs`, `setup_php`, `setup_postgresql`, `setup_mariadb`,
  `setup_mysql`, `setup_mongodb`, `setup_go`, `setup_rust`, `setup_ruby`,
  `setup_uv`, `setup_java`, `setup_clickhouse`, `setup_docker`,
  `setup_composer`, `setup_ffmpeg`, `setup_imagemagick`,
  `setup_meilisearch`, `setup_adminer`, `setup_yq`, `setup_nonfree`,
  `setup_hwaccel`
- `ensure_dependencies` — install Debian or Alpine packages needed for a step
- `create_self_signed_cert`
- `check_for_gh_release`, `check_for_gh_tag`,
  `check_for_codeberg_release`, `check_for_gl_release`
- `cache_installed_version`, `get_cached_version`
- `cleanup_legacy_install`, `remove_old_tool_version`
- `is_package_installed`, `wait_for_apt`

## Common patterns

### Installing dependencies
```bash
msg_info "Installing Dependencies"
$STD apt install -y build-essential libssl-dev redis-server nginx
msg_ok "Installed Dependencies"
```

### Fetching a GitHub release (tarball)
```bash
fetch_and_deploy_gh_release "appname" "owner/repo" "tarball" "latest" "/opt/appname"
```

This extracts a tarball from GitHub releases into `/opt/appname`.

### Fetching a GitHub release (binary/deb)
```bash
fetch_and_deploy_gh_release "appname" "owner/repo" "binary" "latest" "/opt/appname"
```

Matches arch-appropriate `.deb` asset, installs via `apt install`. If no
arch match, scans older releases.

### Updating a GitHub-based app (in `update_script`)
```bash
update_script() {
  header_info
  check_container_storage
  check_container_resources

  if check_for_gh_release "appname" "owner/repo"; then
    msg_info "Stopping $APP"
    systemctl stop appname
    msg_ok "Stopped $APP"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo" "tarball" "latest" "/opt/appname"

    msg_info "Starting $APP"
    systemctl start appname
    msg_ok "Started $APP"
    msg_ok "Updated Successfully!"
  fi
  exit
}
```

### Setting up a runtime
```bash
setup_nodejs
```
or with a specific version:
```bash
NODE_VERSION=20 setup_go
```

### Setting up a database + user
```bash
setup_postgresql
PG_DB_NAME="appname" PG_DB_USER="appname" setup_postgresql_db
```

### Declaring resource defaults
All `var_*` must use `${VAR:-default}` pattern so callers can override:
```bash
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
```

### Credentials stay inside the container
Write passwords to files inside the LXC, then in `post_install_script()`:
```bash
function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}
```

## OS template scripts (Alpine, Debian, etc.)

When a script has no app-specific install logic, the `install_script()` must
still exist (the bootstrap asserts it's defined):

```bash
function install_script() {
  # This space intentionally left blank — build_container handles setup/teardown
}
```

## Porting from upstream (ProxmoxVE / ProxmoxVED)

If you are porting a script from `community-scripts/ProxmoxVED/ct/<app>.sh`:

1. Keep the same `APP`, `var_*`, and the `update_script()` body.
2. Copy the upstream `install/<app>-install.sh` content into `install_script()`.
3. Remove any calls to `$FUNCTIONS_FILE_PATH` / `source install.func` inside
   the install_script body — the framework handles this.
4. Replace raw `apt-get install -y` with `$STD apt install -y`.
5. Replace raw `cd` + `wget`/`tar` for GitHub releases with
   `fetch_and_deploy_gh_release "name" "owner/repo" "tarball" "latest" "/path"`.
6. Remove any calls to `update_os`, `setting_up_container`, `network_check`,
   `motd_ssh`, `cleanup_lxc`, `setup_lxc` (the wrapper postamble handles
   these).
7. Remove any `export` of `$FUNCTIONS_FILE_PATH` or curl of `install.func`.
8. Add `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")` at the bottom.
9. Ensure the file ends with no trailing characters after the bootstrap line.

## Metadata (`_lxc/<slug>.md`)

Every LXC script must have a matching metadata file:

```yaml
---
slug: appname
title: AppName
tags: [tag1, tag2]
logo: /assets/logos/appname.webp
by: GitHubUsername
co_author: [CoAuthor1, CoAuthor2]   # optional
repo: https://github.com/owner/repo
site: https://appname.com
port: 3000
cpu: 2
ram: 2048
disk: 8
maintainer: GitHubUsername
---
```

- **tags** — must match `var_tags` values (semicolons → YAML array)
- **port, cpu, ram, disk** — must match `var_*` defaults in script
- **by** — primary author (matches `# Author:` in script header)
- **co_author** — optional array of co-authors

## Addon scripts

Addon scripts (`scripts/addon/<slug>.sh`) run inside an existing LXC
container. They use `misc/bootstrap/addon` instead of `misc/bootstrap/lxc`.

### Update/uninstall bundle naming

Each addon gets its own self-contained bundles on first install:

| Hook | Bundle destination | Lifecycle |
|------|-------------------|-----------|
| `update_script` | `/usr/local/sbin/update_<slug>` | Persists |
| `uninstall_script` | `/usr/local/sbin/uninstall_<slug>` | Self-destructs on success |

The `<slug>` is derived from `${NSAPP,,}` (lowercased `NSAPP`). Users
trigger updates by running `/usr/local/sbin/update_<slug>` inside the
container.

### Addon script template

```bash
#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: YourName (GitHubUsername)
# License: MIT | <url>
# Source: <url>

APP="AddonName"
var_tags="${var_tags:-tag1}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"

function install_script() {
  msg_info "Installing AddonName"
  # ... addon install steps ...
  msg_ok "Installed AddonName"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  # ... addon update steps ...
  exit
}

function uninstall_script() {
  # ... addon removal steps ...
}

# Addon bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
```

The `install_script` and `post_install_script` run immediately during
addon install. `update_script` and `uninstall_script` are bundled into
self-contained scripts at `/usr/local/sbin/update_<slug>` and
`/usr/local/sbin/uninstall_<slug>` for later use.

## Pre-commit checklist

- [ ] `shfmt -i 2 -ci -sr -w scripts/lxc/<slug>.sh`
- [ ] `shellcheck --severity=warning scripts/lxc/<slug>.sh`
- [ ] `go run ./tools/ast/.` — regenerate AST files (REPO_BASE check runs here)
- [ ] Verify no REPO_BASE violations reported
- [ ] Check that `install_script()` is defined (bootstrap will exit without it)
- [ ] Check all `var_*` use `${VAR:-default}` pattern
- [ ] Check no calls to `start`/`build_container`/`complete_install`
- [ ] Check no inline `msg_info`-like redefinitions (framework provides these)
- [ ] Verify metadata file at `_lxc/<slug>.md` matches script values
