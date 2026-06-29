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

## Stubs for other script types

Addon, PVE, and VM migration patterns are TBD — they will be documented
here once the architecture doc stubs (§3.2-3.4, §4.2-4.4, §5.2-5.4,
§6.2-6.4) are filled.
