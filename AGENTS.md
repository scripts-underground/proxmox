# Contributing to scripts-underground

## Script Architecture

Every script is **single-file** — the container template, install logic, and update logic live in one file. There are no separate install scripts.

### LXC Script (`scripts/lxc/appname.sh`)

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

  fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

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
  ...
  exit
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
```

### Function Order (Required)

Functions must appear in **bootstrap execution order** within the file:

```
install_script()       → runs inside container, app-specific install logic
post_build_script()    → (optional) runs on host after container creation, for pct set / volume mounting
post_install_script()  → runs on host, success message with access URLs
update_script()        → runs inside container on update invocation
uninstall_script()     → (optional) runs inside container on uninstall
```

Utility/helper functions (header_info, msg_*, setup_*, etc.) go before the hook functions.

## Bootstrap Execution Flow

The `misc/bootstrap/lxc` orchestrates execution in this order on the HOST:

```
1. source build.func       → load framework (core.func, tools.func, etc.)
2. variables               → setup prompt variables
3. color                   → define color/formatting vars (GN, CL, INFO, etc.)
4. catch_errors            → error traps
5. start                   → initialize container creation
6. build_container         → create LXC, run install_script() inside container
7. post_build_script()     → optional hook: host-side tweaks (volume mounting, pct commands)
8. description             → set Proxmox GUI description, get container IP
9. post_install_script()   → success messages with access URLs
```

Inside the container, `build_container` runs this order automatically (no need to call these in install_script):

```
setting_up_container → network_check → update_os → install_script() → motd_ssh → customize → cleanup_lxc
```

## Optional Hooks

| Hook | Where | Purpose |
|---|---|---|
| `pre_build_script()` | Host | Pre-flight validation before container creation |
| `post_build_script()` | Host | Post-creation tweaks (`pct set`, volume mounting, etc.) |
| `post_install_script()` | Host | Success messages with access URLs |
| `uninstall_script()` | Container | Uninstall/cleanup logic |

## Copyright Header

Every script must include a copyright header after the REPO_BASE line.
The form depends on whether the script is a migration from upstream or
authored fresh in this repo.

### Migrated scripts (from `community-scripts/ProxmoxVE`)

```bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: OriginalAuthor (GitHubUsername)
# Author: YourName (GitHubUsername)     # only if you significantly modified the script
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://application-url.com
```

- `Copyright` — preserve original upstream attribution
- First `Author` — the original author from upstream
- Second `Author` (optional) — the migrator, added only when the migration involved significant changes to the script (rewrites, non-trivial adaptations, major refactors). Skip for straightforward line-by-line ports.
- `License` — must point to **our** repo's LICENSE file, not upstream
- `Source` — application/project URL

### Net-new scripts (authored in this repo, no upstream ancestry)

```bash
# Copyright (c) 2026 scripts-underground.org
# Author: YourName (GitHubUsername)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://application-url.com
```

- `Copyright` — this repo, current year
- `Author` — you, in `Full Name (github-handle)` form
- `License` — same as migrated
- `Source` — same as migrated

## Metadata (`_lxc/appname.md`)

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

- **tags** — must match upstream `var_tags` values (semicolon-separated in script, converted to YAML array in metadata)
- **by** — primary author (first `# Author:` in upstream)
- **co_author** — optional array of co-authors
- **repo** — upstream repo URL
- **site** — project website (prefer the JSON `website` field over the `# Source:` line when they differ)
- **port**, **cpu**, **ram**, **disk** — must match the `var_*` defaults in the script
- **logo** — either a repo-relative path (`/assets/logos/appname.webp`) or a remote URL. Remote URLs run through the fetch-logos pipeline which fits them into a 512×512 canvas.

When sourcing a logo from the upstream project, prefer in this order:

1. **Filename contains `logo` or `icon`** — banners (`banner`, `hero`, `header` in the filename) are wide and crop poorly.
2. **Square aspect ratio** — round variants are typically inscribed in a square and work well.
3. **Format: PNG > SVG > JPG.**
4. **Prefer light-background variants** when both `-dark` and `-light` exist — the site default theme is light.

Common upstream locations to check, in order:

- `README_images/`, `docs/images/`, `.github/`
- `assets/`, `public/`, `static/`, `cps/static/`, `logos/`
- Site favicon (`<link rel="icon">`) as fallback
- OpenGraph banner or the first README hero image only as last resort — they are almost always wide.

## OS Template Scripts

For OS template scripts (Alpine, Debian, Ubuntu, CentOS, Arch, etc.) that have no app-specific install logic, the `install_script()` must include a comment:

```bash
function install_script() {
  # This space intentionally left blank — build_container handles setup/teardown
}
```

The bootstrap requires `install_script()` to be defined, but `build_container` handles all OS template creation. The comment makes it clear this is intentional, not an oversight.

## Conventions

- **Never contain periods in default hostname** — `var_hostname` must be a simple label (no dots). LXC/PVE can misinterpret periods in hostnames as FQDN boundaries. If the app slug contains periods or is too long, set a short clean default: `var_hostname="${var_hostname:-shortname}"`.
- **No `start`/`build_container`/`description` calls** — the bootstrap handles the flow
- **No `motd_ssh`/`customize`/`cleanup_lxc`** in `install_script()` — `build_container` handles them
- **All `var_*` must use `${var:-default}` pattern** — enables env var overrides
- **Use `$STD`** before all apt/npm/build commands
- **Use `setup_*` functions** for runtimes (nodejs, postgresql, go, rust, python/uv)
- **Use `fetch_and_deploy_gh_release`** instead of curl/wget for GitHub releases
- **Never use Docker** in LXC scripts — bare-metal installation only
- **Never use `sudo`** — scripts run as root inside containers
- **Use `apt`** not `apt-get`
- **Credentials stay inside container** — write to files, reference paths in `post_install_script()`
- **Run `shfmt -i 2 -ci -sr -w`** before committing shell scripts
- **Run `shellcheck --severity=warning`** to catch issues before committing

## Addon / PVE / VM Scripts

Addon, PVE, and VM scripts follow the same function ordering convention as LXC scripts:

```
install_script → post_install_script → update_script → uninstall_script
```

All other conventions (REPO_BASE, copyright header, shfmt formatting, variable patterns) apply to all script types.

## Formatting & Linting

All shell scripts must pass:

```bash
shfmt -i 2 -ci -sr -d scripts/**/*.sh    # check formatting
shfmt -i 2 -ci -sr -w scripts/**/*.sh    # fix formatting
shellcheck --severity=warning scripts/**/*.sh  # lint
```

These checks run in CI (`.github/workflows/deploy.yml`) and as pre-commit hooks (`.pre-commit-config.yaml`).

## Development environment

The devcontainer under `.devcontainer/` is the primary contribution environment. It bundles Ruby/Jekyll, Go (for the AST tool), `pre-commit`, `shellcheck`, and `shfmt`, and wires the pre-commit git hook automatically on `postCreateCommand`. Contributors are expected to work inside the devcontainer for full linting and hook coverage.

Open the devcontainer via VS Code's "Reopen in Container", GitHub Codespaces, or [DevPod](https://devpod.sh/). See `README.md` for details.

For manual / scripted use without an IDE, `.devcontainer/dev.sh` starts the container (building the image on first run) and runs a command inside it:

```bash
.devcontainer/dev.sh bundle exec jekyll build
.devcontainer/dev.sh go run ./tools/ast/.
.devcontainer/dev.sh bash                       # interactive shell
```

The container persists between invocations so Jekyll's live-reload server stays available at http://localhost:4000.

Host-only setups skip the automatic hook installation. If contributing without the devcontainer, install pre-commit manually before your first commit:

```bash
uv tool install pre-commit    # or: pipx install pre-commit
pre-commit install            # wires .git/hooks/pre-commit
```

`shellcheck` and `shfmt` binaries also need to be on `PATH` (e.g., `pacman -S shellcheck shfmt`, `apt install shellcheck shfmt`).

## Regenerating AST files

`_ast/` is committed. CI regenerates on every PR and auto-commits any diff
back to the PR branch so the committed copy always matches the current
extractor.

Regenerate locally with:

    go run ./tools/ast/.

Local edits to `_ast/` are fine — CI overwrites them on the next PR run
if they don't match what the extractor produces from source. If
`go run ./tools/ast/.` exits non-zero, it's reporting a REPO_BASE policy
violation. Read the stderr report and fix the offending script before
committing.
