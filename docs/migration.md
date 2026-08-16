# Migration guide — porting upstream scripts

> Audience: contributors porting scripts from `community-scripts/ProxmoxVED`
> or `community-scripts/ProxmoxVE` into this fork's LXC architecture.
>
> Cross-references: `docs/architecture.md` (the spec), `docs/contributor-guide.md`
> (new-script conventions), `docs/function-reference.md` (available helpers),
> `AGENTS.md` (contributor workflow).

## Overview

Upstream LXC scripts use a **two-file pattern**: a CT script (`ct/<app>.sh`)
plus a separate install script (`install/<app>-install.sh`). The CT script
sources `build.func` at the top, calls framework functions directly, and
ends with `start; build_container; description`. The install script is
fetched fresh at container-creation time and piped into the container via
`lxc-attach`.

This fork uses a **single-file pattern**: one CT script contains everything.
The install logic is inlined into `install_script()`. The bootstrap shim
handles orchestration; the CT script never calls `start`/`build_container`
/`description`. The install script's framework boilerplate (sourcing
`install.func`, calling `color`/`verb_ip6`/`catch_errors`/
`setting_up_container`/`network_check`/`update_os`/`motd_ssh`/
`customize`/`cleanup_lxc`) is handled by the wrapper postamble built
by `build_container`.

A metadata file (`_lxc/<slug>.md` with YAML frontmatter) replaces the
upstream `json/<appname>.json` format.

## Conversion map

| Upstream piece | Fork piece |
|---|---|
| `source <(curl … build.func)` at top of CT script | `REPO_BASE="${REPO_BASE:-…}"` at top of CT script |
| `header_info "$APP"; variables; color; catch_errors` (mid-file) | (removed — bootstrap shim calls these) |
| `install/<app>-install.sh` (separate file) | `install_script()` function body inline in CT script |
| `start; build_container; description` (bottom of CT script) | (removed — bootstrap shim calls these) |
| `msg_ok "Completed Successfully!"` + access URL lines (bottom) | Moved into `post_install_script()` |
| (no final bootstrap source) | `source <(curl … "$REPO_BASE/misc/bootstrap/lxc")` at very bottom |
| `json/<appname>.json` metadata | `_lxc/<slug>.md` with YAML frontmatter |
| API telemetry (post_update_to_api, etc.) | (removed — fork has no telemetry) |
| Resource `var_*` defaults | Same — carried unchanged |

### Install-script preamble to strip

The upstream install script always starts with this block (remove it in full):

```bash
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
```

### Install-script postamble to strip

The upstream install script always ends with this block (remove it in full):

```bash
motd_ssh
customize
cleanup_lxc
```

The framework's wrapper postamble handles all of these around your
`install_script()`.

### Update script — unchanged

The `update_script()` function passes through mostly as-is. The same
`check_for_gh_release` + `fetch_and_deploy_gh_release` + service restart
pattern works unchanged because the framework provides these helpers
inside the container.

### What happens to the bootstrap source line in the CT script

Upstream has no bootstrap source line at the bottom. Fork does. The
`source <(curl … "$REPO_BASE/misc/bootstrap/lxc")` line is the last
line of the script. It replaces the upstream pattern of `source build.func`
at the top and `start; build_container; description` at the bottom.

## Step-by-step procedure

### 1. Read the upstream files

You need:
- `research/ProxmoxVED/ct/<slug>.sh` (the upstream CT script)
- `research/ProxmoxVED/install/<slug>-install.sh` (the upstream install script)
- `research/ProxmoxVED/json/<slug>.json` (the upstream metadata)

### 2. Create the CT script header

```bash
#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
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
```

Replace the upstream source URL with our repo URL in the License line.
Copy `APP`, `var_*`, and the `# Source:` line from the upstream header.

### 3. Create `install_script()` from the install file

Copy the entire install file body, then:

- Remove the shebang (line 1) and copyright header (they're already in
  the CT script).
- Remove the preamble block (`source /dev/stdin … update_os`).
- Remove the postamble block (`motd_ssh; customize; cleanup_lxc`).
- Adjust indentation: wrap everything in a `function install_script() {`
  block with consistent 2-space indent.
- Keep `msg_info`/`msg_ok` pairs and `$STD` prefix usage as-is.
- Keep all `setup_*` and `fetch_and_deploy_*` calls as-is.

### 4. Create or repurpose `update_script()`

The upstream CT script typically has `update_script()` defined mid-file.
Copy it into the fork script as-is. If it doesn't exist, write one.

Common pattern:
```bash
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

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo" "tarball" "latest" "/opt/appname"

    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}
```

### 5. Create `post_install_script()` for the access message

The upstream CT script ends with:

```bash
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:PORT/path${CL}"
```

Move these lines into `post_install_script()`:

```bash
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:PORT/path${CL}"
}
```

Note: `$IP` is available here — it was set by `complete_install` (the
framework function that runs before `post_install_script` fires).

If the upstream has no separate `msg_ok` + access URL block, check
whether the upstream json metadata provides `interface_port`. If so,
write a minimal `post_install_script()`.

### 6. Remove upstream-orchestration lines

Remove from the bottom of the CT script:

```bash
start
build_container
description
```

And remove from the top of the CT script (after the copyright header):

```bash
header_info "$APP"
variables
color
catch_errors
```

### 7. Add the bootstrap source

At the very bottom of the file (last line), add:

```bash
# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
```

### 8. Create the metadata file

Create `_lxc/<slug>.md` with YAML frontmatter. Map the upstream
`json/<slug>.json` fields:

| Upstream JSON field | YAML frontmatter field |
|---|---|
| `name` | `title` |
| `slug` | `slug` |
| `website` | `site` |
| `documentation` | `repo` (if it's a GitHub repo) or `site` (if it's a project website) |
| `install_methods[0].resources.cpu` | `cpu` |
| `install_methods[0].resources.ram` | `ram` |
| `install_methods[0].resources.hdd` | `disk` |
| `interface_port` | `port` |
| `description` | (not mapped — kept in script body markdown) |
| `default_credentials.username` | (not mapped — shown in post_install only) |
| `default_credentials.password` | (not mapped — shown in post_install only) |
| `categories[]` → map numeric IDs to tag strings | `tags` (YAML string array) |
| Author from header `by` | `by` |
| Logo URL → download and reference locally | `logo` (`/assets/logos/<slug>.webp`) |
| `date_created` | (not mapped — git history tracks this) |

Tags category mapping (numeric ID → tag string):

| ID | Tag |
|---|---|
| 0 | misc |
| 1 | proxmox |
| 2 | os |
| 4 | network |
| 5 | adblock-dns |
| 6 | auth-security |
| 7 | backup |
| 8 | database |
| 9 | monitoring |
| 10 | dashboard |
| 11 | files |
| 12 | documents |
| 13 | media |
| 14 | arr-suite |
| 15 | nvr-cameras |
| 16 | iot |
| 17 | zigbee |
| 18 | mqtt |
| 19 | automation |
| 20 | ai-dev |
| 21 | webserver |
| 22 | bots |
| 23 | finance |
| 24 | gaming |
| 25 | business |

Template `_lxc/<slug>.md`:

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

Content area — see existing entries for style.
```

### 9. Pre-commit verification

```bash
shfmt -i 2 -ci -sr -w scripts/lxc/<slug>.sh
shellcheck --severity=warning scripts/lxc/<slug>.sh
go run ./tools/ast/.
```

- Fix any shfmt/shellcheck issues.
- Verify `go run ./tools/ast/.` completes without REPO_BASE violations.
- Verify `grep "bootstrap/lxc" scripts/lxc/<slug>.sh` shows one match at
  the last line.
- Verify `grep "REPO_BASE" scripts/lxc/<slug>.sh | head -1` matches the
  expected pattern.

## Reference: full before/after (affine.sh)

Two files upstream → one file fork.

### Upstream CT script (`ct/affine.sh`, 135 lines)

```
Line 1:  #!/usr/bin/env bash
Line 2:  source <(curl … misc/build.func)       ← remove (replaced by REPO_BASE)
Lines 4-7: Copyright header                      ← keep, update License URL
Line 9:  APP="AFFiNE"                            ← keep
Lines 10-17: var_* block                         ← keep
Line 19: header_info "$APP"                      ← remove
Line 20: variables                               ← remove
Line 21: color                                   ← remove
Line 22: catch_errors                            ← remove
Lines 24-126: update_script()                    ← keep (unmodified)
Line 128: start                                  ← remove
Line 129: build_container                        ← remove
Line 130: description                            ← remove
Line 132: msg_ok "Completed Successfully!\n"     ← move to post_install_script()
Lines 133-135: echo -e access URL lines          ← move to post_install_script()
```

### Upstream install script (`install/affine-install.sh`, 215 lines)

```
Lines 1-6:  Shebang + copyright header           ← remove (in CT script)
Line 8:     source /dev/stdin … FUNCTIONS        ← remove (framework handles)
Lines 9-14: color, verb_ip6, catch_errors,       ← remove (framework handles)
            setting_up_container, network_check,
            update_os
Lines 16-26: msgs + apt install deps             ← keep (→ install_script body)
Lines 28-35: setup_postgresql, setup_nodejs,     ← keep
             setup_rust, fetch_and_deploy
Lines 37-212: build steps, services, nginx       ← keep
Line 213: motd_ssh                               ← remove (framework handles)
Line 214: customize                              ← remove (framework handles)
Line 215: cleanup_lxc                            ← remove (framework handles)
```

### Fork script (`scripts/lxc/affine.sh`, 326 lines)

```
Lines 1-2:   #!/usr/bin/env bash + REPO_BASE     new
Lines 4-7:   Copyright header (License URL changed)
Line 9:      APP="AFFiNE"                        from upstream CT
Lines 10-17: var_* block                         from upstream CT
Lines 19-211: install_script() {                 from install file body
               (preamble stripped, postamble stripped)
             }
Lines 213-219: post_install_script() {           from upstream CT's tail msg_ok
               msg_ok + echo -e access URLs
             }
Lines 221-322: update_script() {                 from upstream CT
               unchanged except indentation
             }
Lines 325-326: # framework bootstrap + source    new
```

## Reference: minimal OS template (alpine.sh)

Upstream CT script (`ct/alpine.sh`, 43 lines):

```
#!/usr/bin/env bash
source <(curl … misc/build.func)                  ← remove
# Copyright header                                ← keep, update License URL
APP="Alpine"                                      ← keep
var_* block                                       ← keep
header_info "$APP"                                ← remove
variables                                         ← remove
color                                             ← remove
catch_errors                                      ← remove
update_script() { … }                            ← keep
start                                             ← remove
build_container                                   ← remove
description                                       ← remove
msg_ok "Completed successfully!\n"                ← move to post_install_script()
```

Upstream install script (`install/alpine-install.sh`, 26 lines):

```
source /dev/stdin … FUNCTIONS                     ← remove
color, verb_ip6, catch_errors,                    ← remove
setting_up_container, network_check, update_os
msg_info "Installing Dependencies"                ← keep (→ install_script)
$STD apk add sudo                                 ← keep
msg_ok "Installed Dependencies"                   ← keep
motd_ssh                                          ← remove
customize                                         ← remove
cleanup_lxc                                       ← remove
```

Fork (`scripts/lxc/alpine.sh`, 37 lines):

```
#!/usr/bin/env bash + REPO_BASE                   new
Copyright header (License URL changed)
APP="Alpine"
var_* block (lower resource defaults)
install_script() {
  msg_info "Installing Dependencies"
  $STD apk add sudo
  msg_ok "Installed Dependencies"
}
post_install_script() {
  msg_ok "Completed successfully!\n"
}
update_script() { … }                            from upstream CT
# framework bootstrap + source                    new
```

## Anti-patterns to fix during migration

Check the upstream install script for these and fix while porting:

- **Docker-based installation** — replace with `fetch_and_deploy_gh_release`
  or setup_* helpers. Never use Docker in LXC scripts.
- **Custom download logic** (`curl`/`wget` + `tar` for GitHub releases) —
  replace with `fetch_and_deploy_gh_release`.
- **Custom version-check logic** — replace with `check_for_gh_release`.
- **Manual runtime installation** — replace with `setup_*` helpers
  (`setup_nodejs`, `setup_go`, `setup_rust`, etc.).
- **`sudo` usage** — remove; scripts run as root inside LXC containers.
- **`apt-get` usage** — replace with `apt`.
- **Core packages listed as dependencies** — remove `curl`, `sudo`, `wget`,
  `jq`, `gnupg`, `ca-certificates`, `mc`. These are already available.
- **Missing `$STD` prefix** — add before all `apt install`, `npm`, `yarn`,
  `make`, `pip` commands.
- **Custom credentials file** — store in `.env` files; don't create
  separate `.creds` files.
- **Backup to `/tmp`** — use `/opt/<app>/.backup/` instead.
- **`systemctl daemon-reload` after a new service file** — not needed
  for first-time service creation.
- **Legacy footer** (`apt-get autoremove` etc.) — replace with the
  framework's `cleanup_lxc` which the wrapper handles.

## Metadata conversion (json/ → _lxc/)

The upstream provides `json/<slug>.json`. Create `_lxc/<slug>.md` with
the fields mapped per the table in step 8. The `logo` field requires
downloading the upstream logo and placing it at `assets/logos/<slug>.webp`.
The `content` area below the frontmatter can be a short description
taken from the upstream JSON's `description` field or the script's
`# Source:` URL.

## Verification checklist

- [ ] `shellcheck --severity=warning` passes
- [ ] `shfmt -i 2 -ci -sr -d` shows no diffs
- [ ] `go run ./tools/ast/.` exits 0 (no REPO_BASE violations)
- [ ] `grep "bootstrap/lxc" scripts/lxc/<slug>.sh` matches exactly once,
      at the file's last line
- [ ] `grep "start\|build_container\|description" scripts/lxc/<slug>.sh | grep -v "^#"` 
      returns nothing (no orchestration calls left in the script)
- [ ] `grep "header_info\|variables\|color" scripts/lxc/<slug>.sh | grep -v "^#"`
      returns nothing (no init calls left in the script)
- [ ] `_lxc/<slug>.md` frontmatter matches script's `var_*` defaults
- [ ] Logo exists at `assets/logos/<slug>.webp`
- [ ] No `${FUNCTIONS_FILE_PATH}` or `install.func` references remain
- [ ] No `motd_ssh`, `customize`, `cleanup_lxc` calls remain in
      `install_script()` body (these are in the wrapper postamble)

## Addon script migration

> Addon scripts come from the upstream `tools/addon/` directory. They run
> INSIDE an existing LXC container (not on the PVE host, not creating a
> container). Target: `scripts/addon/<slug>.sh` + `_addon/<slug>.md`.

### Upstream addon architecture

Upstream addons are single-file but carry an inline dispatch section:

1. Shebang + copyright header, `APP=`, `APP_TYPE="addon"`.
2. Curl-ensure preamble (apk/apt install of curl).
3. `source <(curl …)` × core.func, tools.func, error_handler.func, api.func
   + `init_tool_telemetry` (telemetry — removed here).
4. `set -Eeuo pipefail; trap 'error_handler' ERR`; `load_functions`;
   `header_info`; `get_lxc_ip`.
5. Per-script OS detection block (Alpine vs Debian).
6. `install()` / `update()` / `uninstall()` functions.
7. MAIN section: `type=update` re-entry → per-script "already installed?"
   menu (uninstall/update prompt) → y/n confirm → install. `install()`
   writes a `/usr/local/bin/update_<slug>` stub that **re-curls the
   installer from GitHub** on every update.

### Our replacement

- Hook contract: `install_script()` / `update_script()` / `uninstall_script()`
  (+ optional `post_install_script()`, `header_info()`).
- `misc/bootstrap/addon` + `misc/addon.func` orchestrate; self-contained
  bundles at `/usr/local/sbin/{update,uninstall}_<slug>` (aliased to
  `/usr/bin/`) replace the re-curl stub — frozen at install time,
  offline-capable.
- Install marker `/var/lib/scripts-underground/addons/<slug>`; re-running
  the installer offers update/uninstall/abort via `addon_guard_installed`
  (`ADDON_ACTION` env bypass).

### Host vs container classification

Classify before migrating. Signals in the upstream source:

| Signal | Verdict |
|---|---|
| `require_pve_host`, `pct `, `pveam`, `pvesm`, `qm `, `/etc/pve/` paths, whiptail CT picker | **host** — do NOT migrate as addon (park for the PVE effort) |
| `get_lxc_ip`, container guard, local systemd/openrc service install | **container** — migrate as addon |

Known host scripts (do not port): netdata, add-tailscale-lxc,
add-netbird-lxc, all-templates, coder-code-server, add-iptag.

### Conversion map

| Upstream piece | Fork action |
|---|---|
| Curl-ensure preamble | **Keep minimal version** (apt/apk + hard-fail check) directly above the bootstrap source — the bootstrap line itself needs curl; everything else is framework-bootstrapped |
| 4× `source <(curl …)` + `init_tool_telemetry` | Delete (bootstrap loads framework; no telemetry) |
| `set -Eeuo pipefail; trap 'error_handler' ERR` | Delete (`catch_errors` via install.func `_bootstrap`) |
| `load_functions`, `header_info` call, `ensure_usr_local_bin_persist`, `get_lxc_ip` calls | Delete from body (bootstrap owns); keep `header_info()` *function* if it has ASCII art |
| Per-script Alpine/Debian detection | Framework `detect_os` globals: `OS_FAMILY` (`debian`/`alpine`), `INIT_SYSTEM` (`systemd`/`openrc`) |
| `install()` | `install_script()`; strip its update-stub heredoc and trailing success echoes (→ `post_install_script()`) |
| `update()` | `update_script()`; keep `check_for_gh_release` flow; end with `exit` |
| `uninstall()` | `uninstall_script()`; drop `rm -f /usr/local/bin/update_*` lines (bundle self-destruct owns lifecycle) |
| MAIN section (`type=update`, installed-menu, y/n confirm) | Delete (framework guard + bundles replace it) |
| Interactive prompts (`read` for ports/creds) | **Keep** in `install_script()`, but write `read … \|\| true` + `${var:-default}` (EOF tolerance under `set -e`) |
| `/usr/local/bin/update_<slug>` re-curl heredoc | Delete — bundles replace it |
| Script constants referenced by `update`/`uninstall` (paths, URLs, service users) | Rename to `var_addon_*` with `${var_addon_x:-default}` — baked into bundles |
| Alpine openrc service branches | Keep; branch on `[[ "$INIT_SYSTEM" == "openrc" ]]` |
| `apt-get` / `sudo` | `apt` / remove (container runs as root) |

### Metadata

`_addon/<slug>.md` frontmatter: `slug`, `title`, `tags`, `logo` (remote URL —
CI fetch-logos converts), `by`, `repo`, `site`, `port`, `maintainer`. **No**
`cpu`/`ram`/`disk`. Notes reference the `update-<slug>` / `uninstall-<slug>`
command names.

### Checklist

- [ ] `REPO_BASE=` first, copyright header after (License → our repo)
- [ ] `APP=` set; no `APP_TYPE`, no resource `var_*`
- [ ] `var_addon_*` for every hook-referenced constant
- [ ] curl-ensure block + hard-fail check above bootstrap source
- [ ] `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")` as last line
- [ ] No `init_tool_telemetry` / `api.func` / `type=update` / re-curl stub
- [ ] No per-script OS detection, no inline colors/`msg_*` redefinitions
- [ ] Prompts use `read … || true` + `${var:-default}`
- [ ] `shfmt -i 2 -ci -sr -d` clean, `shellcheck --severity=warning` clean
- [ ] `go run ./tools/ast/.` exits 0
- [ ] `_addon/<slug>.md` matches (tags, port, authors)

## VM script migration

> VM scripts come from the `community-scripts/ProxmoxVE` repository (the
> `vm/` directory). The migration follows the same pattern as LXC: strip
> upstream boilerplate, wrap install logic in `install_script()`, and
> append the bootstrap source line.

### Upstream VM architecture

The upstream VM script is **single-file but monolithic** — all logic runs
inline in the script body. The structure is:

1. Shebang, then `source /dev/stdin … api.func` (telemetry helper).
2. `header_info` function with ASCII art, called immediately.
3. Safety checks (`check_root`, `arch_check`, `pve_check`, `ssh_check`).
4. `default_settings()` / `advanced_settings()` whiptail menus that set
   globals (`MACHINE`, `CPU_TYPE`, `FORMAT`, `START_VM`, `CORE_COUNT`,
   `RAM_SIZE`, `DISK_SIZE`, `HN`, `BRG`, `MAC`, `VLAN`, `MTU`).
5. `start_script()` that presents the default-vs-advanced choice.
6. `pre_build_script()` with user confirmation, calls `start_script()`.
7. `post_to_api_vm` (telemetry).
8. Storage selection loop (inline, not a function).
9. Image download via `curl` (inline).
10. Storage-type detection case block (inline).
11. `qm create` — reads globals directly (`${MACHINE}`, `${CPU_TYPE}`,
    `${CORE_COUNT}`, `${RAM_SIZE}`, `${HN}`, `${BRG}`, `${MAC}`).
12. `pvesm alloc`, `qm importdisk`, `qm set`, `qm resize`.
13. `if [ "$START_VM" == "yes" ]; then qm start; fi`.
14. `post_update_to_api "done"` (telemetry).
15. `msg_ok "Completed successfully!\n"` + access message.

### Fork VM architecture

The fork replaces the **inline qm commands** with lifecycle functions
in `misc/vm.func`. The VM bootstrap shim (`misc/bootstrap/vm`) sources
framework files and calls lifecycle functions in order:

```
source build.func + vm.func
  → guard (check install_script defined)
  → vm_validate
  → vm_init_colors
  → render_header
  → catch_errors
  → vm_setup
  → vm_create
  → vm_start
  → complete_install
```

The VM script supplies:

- **`header_info()`** (optional) — custom ASCII art. If defined,
  `render_header()` dispatches to it; otherwise a generic fallback
  displays `$APP`.
- **`install_script()`** — app install logic (executed via SSH into
  the running VM, injected by `vm_inject_install()`).
- **`update_script()`** — update logic (same pattern as LXC).
- **`post_install_script()`** — final message and access URL.
- **`default_settings()` / `advanced_settings()`** (or just
  `pre_build_script` hook) — set VM globals.

### Conversion map

| Upstream piece | Fork piece |
|---|---|
| `source /dev/stdin … api.func` | `REPO_BASE="${REPO_BASE:-…}"` |
| `header_info()` with ASCII art | ✅ Copy — `render_header()` dispatches to it |
| `header_info` invocation at start | 🔄 Replaced by `render_header` call in bootstrap |
| `echo -e "\n Loading..."` | ✅ Copy |
| `GEN_MAC=02:$(openssl rand …)` | 🏭 In `vm.func` (line 1) |
| `RANDOM_UUID`, `METHOD`, `NSAPP` | ❌ Removed (telemetry) |
| `var_os`, `var_version` | ✅ Copy |
| ANSI color variables (YW, BL, etc.) | 🏭 `vm_init_colors()` in `vm.func` |
| Emoji prefix variables (CM, CROSS, etc.) | 🏭 `vm_init_colors()` in `vm.func` |
| `set -e` | 🏭 `catch_errors()` in `error_handler.func` |
| `trap 'error_handler …' ERR` | 🏭 `catch_errors()` |
| `trap cleanup EXIT` | 🏭 `catch_errors()` |
| `trap 'post_update_to_api …' SIGINT/SIGTERM/SIGHUP` | ❌ Removed (telemetry) |
| `header_info()` function | ✅ Copy (custom ASCII art) |
| `error_handler()` function | 🏭 `error_handler` in `error_handler.func` |
| `get_valid_nextid()` function | 🏭 `pvesh get /cluster/nextid` (inline if needed) |
| `cleanup_vmid()` function | 🏭 `vm_create` handles cleanup |
| `cleanup()` function | 🏭 `on_exit` in `error_handler.func` |
| `msg_info()`, `msg_ok()`, `msg_error()` functions | 🏭 `core.func` |
| `check_root()` function | 🏭 `vm_validate()` in `vm.func` |
| `arch_check()` function | 🏭 `vm_validate()` in `vm.func` |
| `pve_check()` function | 🏭 `vm_validate()` in `vm.func` |
| `ssh_check()` function | 🏭 `vm_validate()` in `vm.func` |
| `exit-script()` function | 🏭 `exit_script` in `build.func` |
| `start_script()` function | ✅ Copy — called by `pre_build_script` hook |
| `default_settings()` function | ✅ Copy — sets `VM_` globals |
| `advanced_settings()` function | ✅ Copy — sets `VM_` globals (remove `METHOD=` line) |
| `whiptail --title "This will create …"` confirmation | 📝 Move into `pre_build_script()` hook |
| `check_root; arch_check; pve_check; ssh_check` inline | ❌ Remove (handled by `vm_validate()`) |
| `start_script` inline call | 📝 Move into `pre_build_script()` hook |
| `post_to_api_vm` inline call | ❌ Remove (telemetry) |
| Storage selection loop (inline) | 🏭 `vm_select_storage()` in `vm.func` |
| `URL=…`, `curl …` image download (inline) | 🏭 `vm_download_image()` in `vm.func` |
| `FILE=$(basename $URL)` | 🏭 `vm.func` sets `VM_FILE` |
| Storage-type case block (DISK_EXT, DISK_IMPORT, THIN) | 🏭 `vm_create()` in `vm.func` |
| `qm create $VMID … ${MACHINE} ${CPU_TYPE} …` (inline) | 🏭 `vm_create()` in `vm.func` |
| `pvesm alloc …` (inline) | 🏭 `vm_create()` in `vm.func` |
| `qm importdisk …` (inline) | 🏭 `vm_create()` in `vm.func` |
| `qm set … -efidisk0 … -scsi0 …` (inline) | 🏭 `vm_create()` in `vm.func` |
| `qm set -description` (HTML block, inline) | 🏭 `vm_create()` in `vm.func` |
| `qm resize …` (inline) | 🏭 `vm_create()` in `vm.func` |
| `if [ "$START_VM" == "yes" ]; then qm start; fi` | 🏭 `vm_start()` reads `VM_START` |
| `post_update_to_api "done"` | ❌ Removed (telemetry) |
| `msg_ok "Completed successfully!\n"` + access message | 📝 Move into `post_install_script()` |
| (no final bootstrap) | `source <(curl … "$REPO_BASE/misc/bootstrap/vm")` |

### Variable contract

Every global the VM script sets for `vm.func` to read must use the
`VM_` prefix. This prevents accidental namespace collisions with LXC
globals set by `build.func`.

| Script sets | `vm.func` reads | Purpose | Example value |
|---|---|---|---|
| `VM_VMID` | `${VM_VMID}` | VM ID | `100` |
| `VM_STORAGE` | `${VM_STORAGE}` | Storage pool | `local-lvm` (set by `vm_select_storage()`) |
| `VM_MACHINE` | `${VM_MACHINE:-}` | Machine type | `""` or `" -machine q35"` |
| `VM_CPU` | `${VM_CPU:-}` | CPU model | `""` or `" -cpu host"` |
| `VM_DISK_FORMAT` | `${VM_DISK_FORMAT:-qcow2}` | EFI disk format | `""` or `",efitype=4m"` |
| `VM_START` | `${VM_START:-yes}` | Auto-start after creation | `"yes"` or `"no"` |
| `VM_OSTYPE` | `${VM_OSTYPE:-l26}` | OS type for qm | `"l26"` |
| `VM_BIOS` | `${VM_BIOS:-ovmf}` | BIOS type | `"ovmf"` or `"seabios"` |
| `VM_URL` | `${VM_URL:-}` | Image download URL | `https://cloud-images.ubuntu.com/…` |
| `VM_CLOUD_INIT` | `${VM_CLOUD_INIT:-yes}` | Enable cloud-init | `"yes"` or `"no"` |
| `VM_DISK_CACHE` | `${VM_DISK_CACHE:-}` | Disk cache | `""` or `"cache=writethrough,"` |
| `VM_CORE_COUNT` | `${VM_CORE_COUNT:-2}` | CPU cores | `2` |
| `VM_RAM_SIZE` | `${VM_RAM_SIZE:-2048}` | RAM in MB | `2048` |
| `VM_DISK_SIZE` | `${VM_DISK_SIZE:-10G}` | Disk size | `"10G"` |
| `VM_HN` | `${VM_HN:-vm}` | Hostname | `"ubuntu"` |
| `VM_BRG` | `${VM_BRG:-vmbr0}` | Bridge | `"vmbr0"` |
| `VM_MAC` | `${VM_MAC:-$GEN_MAC}` | MAC address | `"02:AA:BB:CC:DD:EE"` |
| `VM_VLAN` | `${VM_VLAN:-}` | VLAN tag | `""` or `",tag=100"` |
| `VM_MTU` | `${VM_MTU:-}` | MTU size | `""` or `",mtu=1500"` |

### Migration checklist

Copy or strip each upstream element below. Check off as you go. Any
item left unchecked must be explained in a comment or commit message.

#### Sourcing

- [ ] Shebang (`#!/usr/bin/env bash`) added
- [ ] `REPO_BASE="${REPO_BASE:-…}"` at top (replaces `source … api.func`)
- [ ] Copyright header kept, License URL updated to fork repo
- [ ] `source <(curl … "$REPO_BASE/misc/bootstrap/vm")` at last line
- [ ] `# shellcheck disable=SC1090` added above bootstrap source line

#### Signals and safety

- [ ] `set -e` removed (handled by `catch_errors`)
- [ ] `trap 'error_handler …' ERR` removed (handled by `catch_errors`)
- [ ] `trap cleanup EXIT` removed (handled by `on_exit`)
- [ ] `trap 'post_update_to_api …' SIGINT/SIGTERM/SIGHUP` removed (telemetry)

#### Functions — copy from upstream

- [ ] `header_info()` — custom ASCII art (copy; must NOT be named `header_info_fallback`)
- [ ] `start_script()` — default-vs-advanced choice
- [ ] `default_settings()` — VM globals (rename to new `VM_` names)
- [ ] `advanced_settings()` — whiptail menus (rename to new `VM_` names; remove `METHOD=`)

#### Functions — remove (handled by framework)

- [ ] `error_handler()` — handled by `error_handler.func`
- [ ] `get_valid_nextid()` — handled by `pvesh get /cluster/nextid`
- [ ] `cleanup_vmid()` — handled by `vm_create`
- [ ] `cleanup()` — handled by `on_exit`
- [ ] `msg_info()` / `msg_ok()` / `msg_error()` — handled by `core.func`
- [ ] `check_root()` — handled by `vm_validate`
- [ ] `arch_check()` — handled by `vm_validate`
- [ ] `pve_check()` — handled by `vm_validate`
- [ ] `ssh_check()` — handled by `vm_validate`
- [ ] `exit-script()` — handled by `exit_script`

#### Variables — copy with rename

For each, rename from the upstream name to the `VM_`-prefixed fork name
in both `default_settings()` and `advanced_settings()`:

- [ ] `MACHINE` → `VM_MACHINE`
- [ ] `CPU_TYPE` → `VM_CPU`
- [ ] `FORMAT` → `VM_DISK_FORMAT`
- [ ] `START_VM` → `VM_START`
- [ ] `CORE_COUNT` → `VM_CORE_COUNT`
- [ ] `RAM_SIZE` → `VM_RAM_SIZE`
- [ ] `DISK_SIZE` → `VM_DISK_SIZE`
- [ ] `DISK_CACHE` → `VM_DISK_CACHE`
- [ ] `HN` → `VM_HN`
- [ ] `BRG` → `VM_BRG`
- [ ] `MAC` → `VM_MAC`
- [ ] `VLAN` → `VM_VLAN`
- [ ] `MTU` → `VM_MTU`

#### Variables — remove

- [ ] `RANDOM_UUID` removed (telemetry)
- [ ] `METHOD` removed (telemetry)
- [ ] `NSAPP` removed (telemetry)
- [ ] `THIN` removed (`vm.func` determines internally)
- [ ] `DISK0`, `DISK1`, `DISK0_REF`, `DISK1_REF` removed (`vm.func` computes)
- [ ] `DISK_EXT`, `DISK_REF`, `DISK_IMPORT` removed (`vm.func` determines from storage type)
- [ ] `GEN_MAC` removed (defined in `vm.func`)

#### Inline commands — remove (handled by `vm.func`)

- [ ] Storage selection loop (replaced by `vm_select_storage()`)
- [ ] Image download (`URL=…`, `curl …`, `FILE=…`) (replaced by `vm_download_image()`)
- [ ] Storage-type case block (DISK_EXT, DISK_IMPORT, THIN)
- [ ] `qm create $VMID … ${MACHINE} ${CPU_TYPE} …`
- [ ] `pvesm alloc …`
- [ ] `qm importdisk …`
- [ ] `qm set … -efidisk0 … -scsi0 …`
- [ ] `qm set -description` (HTML payload)
- [ ] `qm resize …`
- [ ] `if [ "$START_VM" == "yes" ]; then qm start; fi`

#### Inline calls — remove

- [ ] `header_info` at top of script (replaced by `render_header` in bootstrap)
- [ ] `check_root; arch_check; pve_check; ssh_check` (handled by `vm_validate`)
- [ ] `start_script` (moved into `pre_build_script`)
- [ ] `post_to_api_vm` (telemetry)
- [ ] `post_update_to_api "done"` (telemetry)

#### Inline content — move to hooks

- [ ] `msg_ok "Completed successfully!\n"` — move to `post_install_script()`
- [ ] Access URL / cloud-init message — move to `post_install_script()`
- [ ] Confirmation prompt `whiptail --title "This will create …"` — move to `pre_build_script()`

### Step-by-step

#### 1. Start from the upstream VM script

Your template is `research/ProxmoxVE/vm/<slug>.sh`.

#### 2. Create the header

```bash
#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://app-url.com

APP="AppName"
VM_OSTYPE="${VM_OSTYPE:-l26}"
VM_BIOS="${VM_BIOS:-ovmf}"

var_os="osname"
var_version="version"
```

#### 3. Copy `header_info()` with ASCII art

Copy the entire `header_info` function block. Keep it as-is. The
framework's `render_header()` will dispatch to it.

#### 4. Rename globals to `VM_` prefix

In `default_settings()` and `advanced_settings()`, rename every relevant
variable (see the checklist above). For example:

- `MACHINE=""` → `VM_MACHINE=""`
- `CPU_TYPE=""` → `VM_CPU=""`
- `FORMAT=",efitype=4m"` → `VM_DISK_FORMAT=",efitype=4m"`
- `START_VM="yes"` → `VM_START="yes"`
- `CORE_COUNT="2"` → `VM_CORE_COUNT="2"`
- `HN="ubuntu"` → `VM_HN="ubuntu"`
- `MAC="$GEN_MAC"` → `VM_MAC=""` (default set inside `vm.func`)
- etc.

Remove the `METHOD=` line (telemetry).

#### 5. Wrap inline logic

Create `pre_build_script()` that wraps the upstream inline flow before
the `qm create` block:

```bash
function pre_build_script() {
  header_info
  echo -e "\n Loading..."

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP} VM" \
    --yesno "This will create a new ${APP} VM. Proceed?" 10 58; then
    :
  else
    header_info && exit_script
  fi

  start_script
  VM_CLOUD_INIT="${VM_CLOUD_INIT:-yes}"
}
```

`start_script()` itself is copied as-is from upstream (it chooses
default vs advanced). `default_settings()`/`advanced_settings()` use
the renamed `VM_` globals.

#### 6. Create `post_install_script()`

Move the upsteam tail (`msg_ok "Completed successfully!\n"`, access
URL, cloud-init message) into a `post_install_script()` function:

```bash
function post_install_script() {
  msg_ok "Created a ${APP} VM ${CL}${BL}(${VM_HN})"
  msg_ok "Completed successfully!\n"
  msg_info "Setup Cloud-Init before starting"
  msg_info "More info at https://github.com/community-scripts/ProxmoxVE/discussions/272"
}
```

#### 7. Create `install_script()` (optional)

If the VM requires software installation via SSH, define
`install_script()`. The framework injects it via `vm_inject_install()`.

#### 8. Create `update_script()` (optional)

Same pattern as LXC — copied from upstream, unchanged.

#### 9. Add the bootstrap source

```bash
# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/vm")
```

#### 10. Verification

```bash
shfmt -i 2 -ci -sr -w scripts/vm/<slug>.sh
shellcheck --severity=warning scripts/vm/<slug>.sh
go run ./tools/ast/.
```

### Anti-patterns

Check the upstream VM script for these and fix while porting:

- **`METHOD=""` left behind** — always remove; it was only used for telemetry.
- **Old variable names (`MACHINE`, `CPU_TYPE`, `FORMAT`) instead of `VM_` prefix** —
  every upstream global must be renamed.
- **Inline `qm create` / `qm set` commands** — always replaced by `vm.func`
  (`vm_create` handles all VM lifecycle commands).
- **`source … api.func` or `post_to_api_vm` / `post_update_to_api` calls** —
  removed; fork has no telemetry.
- **Inline `header_info` at script start** — removed; `render_header` in
  the bootstrap handles this.
- **`header_info` function named `header_info_fallback`** — keep the function
  name `header_info` for the dispatch; `header_info_fallback` is the
  framework's internal generic, not the script concern.
- **Storage selection loop copied inline** — replaced by
  `vm_select_storage()` from `vm.func`.
- **`GEN_MAC` redefined** — removed; `vm.func` defines it.
- **`DISK_EXT` / `DISK_REF` / `DISK_IMPORT` / `THIN` assigned** — removed;
  `vm_create()` determines these internally from storage type.
- **Inline image download (URL, curl, FILE, sleep)** — replaced by
  `vm_download_image()`.
- **`rm -rf $TEMP_DIR`** — removed; framework handles cleanup.
- **`popd` at end** — removed; no inline `pushd` needed.
- **ASCII art rendered inline without `header_info()` wrapper** — wrap in
  `function header_info() { cat <<"EOF" … EOF }` so `render_header` can
  dispatch to it.

### Lifecycle flow summary

```
vm_validate            → checks root, arch, PVE version, SSH env
vm_init_colors         → ANSI color and emoji variables
render_header          → dispatches to script's header_info() or fallback
catch_errors           → installs traps (safe to call after display starts)
vm_setup               → calls pre_build_script hook (settings, confirmation)
vm_create              → qm create + importdisk + set + resize; reads VM_ globals
vm_start               → qm start if VM_START=yes
complete_install       → fires post_install_script hook
```

### Verification checklist

- [ ] `shellcheck --severity=warning` passes (add `# shellcheck disable=SC2034`
      on `APP` assignment — the framework reads it, shellcheck can't see it)
- [ ] `# shellcheck disable=SC1090` above the bootstrap source line
- [ ] `shfmt -i 2 -ci -sr -d` shows no diffs
- [ ] `go run ./tools/ast/.` exits 0 (no violations)
- [ ] No `METHOD=`, `NSAPP=`, `post_to_api_vm`, `post_update_to_api`,
      `post_to_api` anywhere
- [ ] No inline `qm create`, `qm importdisk`, `qm set`, `qm resize`,
      `pvesm alloc`
- [ ] No `GEN_MAC`, `DISK_EXT`, `DISK_REF`, `DISK_IMPORT`, `THIN`,
      `DISK0`, `DISK1`, `DISK0_REF`, `DISK1_REF`
- [ ] No `source /dev/stdin`, `source … api.func`
- [ ] No `header_info` call at top of script (outside `pre_build_script` or
      `start_script`)
- [ ] No `check_root`, `arch_check`, `pve_check`, `ssh_check` inline
- [ ] Every global in `default_settings()` / `advanced_settings()` uses
      `VM_` prefix
- [ ] `bootstrap/vm` on the last line
- [ ] `post_install_script()` exists with completion message and access info
- [ ] `pre_build_script()` exists with confirmation prompt + `start_script` call
