# Architecture — LXC scripts

> Audience: maintainers of `misc/build.func`, the bootstrap shims, and the
> LXC framework.
>
> Scope: LXC scripts. Addon, PVE, and VM types are stubbed here and will be
> detailed in a future pass.

## 1. Overview

Each script in this repo is a single file. The user's CT script declares
configuration variables (APP, resource defaults) and bash functions that
serve as lifecycle hooks (install_script, update_script, etc.). The script
ends with `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")`, which
loads the framework and runs the install path.

The bootstrap shim is the orchestrator. It loads the framework files,
guards preconditions, and invokes framework functions — it does not call
user hooks directly. Framework functions own their respective lifecycle
stages and invoke the appropriate user hooks as part of their work.

## 2. The four script types

- **LXC** — creates a full LXC container on the Proxmox host, runs
  install logic inside it, finalizes with metadata and success messages.
  This document covers LXC in detail.

- **Addon** — runs inside an existing LXC (the user has an already-running
  container and wants to install something into it). Own bootstrap
  (`misc/bootstrap/addon_lxc`) and framework module (`misc/addon_lxc.func`).
  Install is guarded by a marker; update/uninstall run as self-contained
  bundles baked at install time.

- **PVE** — runs on the Proxmox host directly (no container creation).
  Procedural scripts that use the framework as a utility library.
  No hook contract.

- **VM** — creates a Proxmox VM, injects install logic via SSH.
  Different boostrap, different orchestration.
  No hook contract in the LXC sense.

## 3. Bootstrap shims

### 3.1 LXC — `misc/bootstrap/lxc`

The spec'd shim (with migration applied):

```bash
source <(curl -fsSL "${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}/misc/build.func") 2>/dev/null

declare -F install_script >/dev/null || {
  echo "Error: install_script() not defined"
  exit 1
}

variables
color
catch_errors

start
build_container
complete_install
```

Every line is `source`, a guard, or a framework function call. No user
hooks invoked directly.

- Line 1 sources `build.func`, which as a side effect pulls in
  `core.func` and `error_handler.func` and runs setup
  code (`load_functions`, `catch_errors`).

- Lines 3–6 assert the user defined `install_script`. Required; fail fast
  if absent.

- Lines 8–10 set up the framework's global state: normalized app
  identifiers, ANSI color vars, strict-mode error traps.

- Line 12 — `start` dispatches by context. On the Proxmox host it runs
  the whiptail menu (via `setup_script`) to collect container settings.
  Inside an existing container it runs the update flow instead.
  If `start` returns, the install path continues.

- Line 13 — `build_container` creates the LXC, runs the app installer
  inside it, checks the result, fires `post_build_script`.

- Line 14 — `complete_install` queries the container for network info,
  sets the PVE web-UI description, fires `post_install_script`, prints
  the final success message.

#### Hooks owned by framework functions

| Hook | Owner | Runs |
|------|-------|------|
| `header_info` | `render_header` | Host, early in bootstrap |
| `pre_build_script` | `build_container` | Host, before LXC creation |
| `install_script` | `build_container` | Container, via install bundle (self-destructs) |
| `post_build_script` | `build_container` | Host, after install completes |
| `post_install_script` | `complete_install` | Host, as final step |
| `update_script` | — | Container, via `/usr/local/sbin/update` (persistent bundle; aliased to `/usr/bin/update` so bare `update` works in minimal-PATH shells like `pct enter`) |
| `uninstall_script` | — | Container, via `/usr/local/sbin/uninstall` (self-destructs on success) |

#### Hooks NOT invoked by the shim

`update_script` and `uninstall_script` are not part of the install path.
They are invoked from inside the container later via self-contained
bundles pushed at install time:
- **Update**: `/usr/local/sbin/update` (persists after install)
- **Uninstall**: `/usr/local/sbin/uninstall` (self-destructs on success)
- **Addon variants**: `/usr/local/sbin/update_<slug>`,
  `/usr/local/sbin/uninstall_<slug>` (same lifecycle rules)

Each bundle carries its own **runtime context**, baked at build time from the
host shell: `APP`, `NSAPP`, `REPO_BASE`, and any `var_lxc_*` variables the
script has declared. Hooks may reference these directly. The context block
appears after `set -euo pipefail` and before the inlined framework files.

`header_info` is not a lifecycle hook — it's a display hook invoked by
`render_header()` early in the bootstrap (after `color` / `vm_init_colors`,
before `catch_errors`). If the script defines `header_info()`, the
framework's `render_header()` dispatches to it; otherwise a generic
fallback (`header_info_fallback()`) displays the app name.

### 3.2 Addon — `misc/bootstrap/addon_lxc`

The addon shim runs INSIDE an existing LXC container. Every line is a source,
a guard, or a framework function call:

```bash
source install.func   # self-bootstraps: core+error_handler, load_functions,
                      # catch_errors, get_lxc_ip, detect_os
source tools.func     # fetch_and_deploy_*, setup_*, check_for_gh_release
source github.func    # clone_and_deploy_gh_commit, token helpers
source addon_lxc.func

command -v addon_guard || FATAL   # explicit failure if a fetch went silent
addon_guard          # container-only check
addon_init           # APP_SLUG derivation, render_header
addon_dispatch       # installed-guard → install path
```

Ordering notes:

- A script-defined `header_info()` survives framework sourcing: `core.func`'s
  same-named fallback stub is guarded (`declare -F` check), so
  `render_header` dispatches to the script's ASCII art.
- `install.func`'s `_bootstrap` runs at source time and calls `catch_errors`
  before `render_header` — the reverse of the LXC ordering. Acceptable: the
  addon path has no whiptail stage that could conflict with active traps.
- `source <(curl …)` via process substitution swallows curl failures (empty
  input sources cleanly). The `command -v addon_guard` check turns a silent
  empty-source into an explicit fatal error.
- The script itself must ensure `curl` exists before the bootstrap line
  (containers may lack it). This is the one per-script preamble block —
  everything else is framework-owned.

#### Hooks owned by framework functions

| Hook | Owner | Runs |
|------|-------|------|
| `header_info` | `render_header` (dispatches to script's art or fallback) | Container, early |
| `install_script` | `addon_run_install` (mandatory) | Container, install path |
| `post_install_script` | `addon_run_install` (optional) | Container, after install |
| `update_script` | bundle `/usr/local/sbin/update_<slug>` | Container, on demand |
| `uninstall_script` | bundle `/usr/local/sbin/uninstall_<slug>` | Container, on demand |

`update_script`/`uninstall_script` are also reachable through
`addon_guard_installed` when the installer is re-run on a container that
already has the addon (menu dispatches via `exec` into the on-disk bundles).


### 3.3 PVE — `misc/bootstrap/pve`

**TBD** — see migration plan.

### 3.4 VM — `misc/bootstrap/vm`

**TBD** — see migration plan.

## 4. Install path

### 4.1 LXC install path

Waterfall diagram (time flows top to bottom, host left / container right):

```
HOST                                       | CONTAINER
                                           |
CT script begins                           |
  declares APP, var_*, install_script      |
  declares optional hooks                  |
                                           |
source bootstrap/lxc                       |
  source build.func                        |
  assert install_script defined            |
  variables, color, catch_errors           |
                                           |
start                                      |
  → setup_script (whiptail menu)           |
  ← collects CTID, settings                |
                                           |
build_container                            |
  → pre_build_script    ◀ USER HOOK        |
  → pct create   ──────────────────────────→ container exists
  → pct start    ──────────────────────────→ container running
  → install base packages via pct exec ────→ base ready
  → compose install wrapper from           |
      declare -f install_script            |
  → compose update + uninstall wrappers    |
  → pct push wrappers ─────────────────────→ files in /tmp
                                           |
  → lxc-attach run install wrapper ────────→ wrapper runs:
                                           |   source framework files (re-curl)
                                           |   setup container basics
                                           |   install_script   ◀ USER HOOK
                                           |   motd_ssh, setup_lxc, cleanup_lxc
                                           |   write failure flag on error
  ←───────────────────────────────────── returns
  → check flag                             |
  → post_build_script  ◀ USER HOOK         |
                                           |
complete_install                           |
  → query container for IP ────────────────→ responds
  → set PVE description ───────────────────→
  → post_install_script  ◀ USER HOOK       |
  → msg_ok "Completed Successfully!"       |
                                           |
DONE                                       |
```

#### 4.1.1 Host setup

The CT script runs on the Proxmox host. By the time bash reaches the
`source bootstrap/lxc` line at the bottom of the script, the user's
`install_script` and any optional hooks are defined in the running shell.
From there, the shim's job during host setup is to load the framework and
prepare global state for the rest of the install path.

It does this in three moves. First, it sources `build.func`, which is the
LXC framework's main file — and which, as a side effect of being sourced,
pulls in several smaller framework files and runs setup code. Second, it
sanity-checks that the user actually defined `install_script`; without
that function there is no app to install, so the shim fails fast. Third,
it runs three framework calls that set up the global state the rest of
the install path relies on: normalized application identifiers, color and
message-glyph vars for terminal output, and strict-mode error traps.

When this stage ends, the host shell holds: the user's hook functions,
the framework's helpers, and the global vars (APP, NSAPP, SESSION_ID,
color vars, etc.) that downstream stages will read.

#### 4.1.2 `start` dispatch

After host setup, the shim calls `start`. This is the install path's
first conditional branch. The shim doesn't know whether the user is
creating a new LXC or updating an existing one — that's `start`'s job.

`start` detects context by checking whether the `pveversion` command
exists. On a Proxmox host it does; inside an existing container it
doesn't. Two outcomes:

- **Host context**: `start` runs the menu function (`setup_script`),
  which presents the whiptail UI and collects settings. Control returns
  to the shim.
- **Container context**: `start` runs the update flow (silent or
  interactive), calling the user's `update_script`. The script exits
  there; control never returns to the shim.

From the shim's perspective, `start` either returns (install path
continues) or the script exits. No return value is inspected.

#### 4.1.3 `setup_script` and the whiptail menu

After `start` decides the install path, control passes to `setup_script`.
Its job is to collect every parameter the LXC create command needs:
container ID, hostname, storage, disk size, CPU/RAM, network, password.

A whiptail menu offers a top-level choice — Default Install (use the
script's declared `var_*` defaults), Advanced Install (~30 dialogs for
individual settings), or User Defaults (re-use a previously-saved set).
Each option populates the same set of global variables; only the source
of the values differs.

When `setup_script` returns, the host shell holds a fully-populated set
of container settings the next stage will consume.

#### 4.1.4 `build_container` orchestration

This is the install path's main work. `build_container` takes the
populated settings and the user's hook functions and produces a running
LXC with the app installed inside.

Stages, in order:

1. Optionally invoke the user's `pre_build_script` on the host.
2. Compose the full `pct create` argument string from settings
   (network, cores, memory, storage, features, and so on).
3. Run `pct create` to instantiate the container. If the template
   isn't cached locally, download it first.
4. Start the container, wait for network connectivity.
5. Install base packages inside the container via `pct exec`
   (bash, curl, sudo, jq, etc. — distro-dependent).
6. Build self-contained bundles via `build_bundle()`:
   - **Install bundle** (`/tmp/install-bundle.sh`): inlines all 4
     framework `.func` files + `install_script` hook + install
     pipeline. Self-destructs on completion via `trap ... EXIT`.
   - **Update bundle** (`/usr/local/sbin/update`): inlines framework
     + `update_script` hook. Persists for future updates.
   - **Uninstall bundle** (`/usr/local/sbin/uninstall`): inlines
     framework + `uninstall_script` hook. Self-destructs on success.
7. Push all bundles into the container via `pct push`.
8. Execute the install bundle via `lxc-attach`.
9. Check the failure flag that the bundle writes on error.
10. Invoke the user's `post_build_script` on the host.

`pre_build_script` and `post_build_script` are the only user hooks
called from inside `build_container`.

#### 4.1.5 Bundle composition

The user's hook functions (`install_script`, `update_script`,
`uninstall_script`) are bash functions defined in the host shell. They
must execute inside the new LXC, in a different bash process spawned via
`lxc-attach`. Bash function definitions don't cross process boundaries —
the framework must transport the function bodies explicitly.

The `build_bundle()` function in `misc/bundle.func` assembles each bundle:

1. **Cache framework libs on the host** (once per session):
   `core.func`, `error_handler.func`, `install.func`, `tools.func` are
   fetched from `$REPO_BASE` and verified (size > 100 bytes, sentinel
   functions present).

2. **Inline everything into a single script**:
   - Shebang, `set -euo pipefail`, `set -x`
   - `_wrap_log` with a per-bundle tag (`INST`, `UPDA`, `UNIN`)
   - All 4 framework `.func` files, verbatim, between `# ═══` markers
   - Sanity checks that the expected sentinel functions loaded
   - `load_functions`, `catch_errors`, `color`
   - `declare -f <hook>` — the function body extracted via `declare -f`
   - Role-specific pipeline and footer:
     - **Install**: `trap 'rm -f "${BASH_SOURCE[0]}"' EXIT` +
       `setting_up_container`, `network_check`, `update_os`,
       `install_script`, `motd_ssh`, `setup_lxc`, `cleanup_lxc`
     - **Update**: just `update_script` — no self-destruct
     - **Uninstall**: `if uninstall_script; then rm -f "${BASH_SOURCE[0]}"; fi`

3. **Push into the container** via `pct push` and set the execution mode.

No network I/O happens inside the container for framework loading — all
libraries are already part of the bundle file. Each bundle is fully
self-contained once it leaves the host.

#### 4.1.6 In-container execution and exit-flag check

The wrapper runs inside the container and either succeeds or fails.
The framework needs a reliable signal — `lxc-attach`'s exit code is not
always trustworthy across versions and container states.

The framework uses a sentinel file instead. The wrapper writes
`/root/.install-${SESSION_ID}.failed` if an error occurs. After
`lxc-attach` returns, the host-side code checks for this file and treats
its presence as a definitive failure, regardless of `lxc-attach`'s exit
code.

The wrapper writes the flag on any unhandled error (the wrapper runs with
error traps enabled from `core.func`/`error_handler.func`). Any future
modification to the wrapper prelude or postamble must respect this
convention — new error paths must write the failure flag to prevent
silently swallowed failures.

#### 4.1.7 Persistent update and uninstall bundles

While assembling the install bundle, `build_container` also assembles
update and uninstall bundles:

| Bundle | Destination inside container | Lifecycle |
|--------|------------------------------|-----------|
| Install | `/tmp/install-bundle.sh` | Self-destructs on EXIT (success or failure) |
| Update | `/usr/local/sbin/update` | Persists — user runs it directly |
| Uninstall | `/usr/local/sbin/uninstall` | Self-destructs on successful uninstall |

The update bundle is a first-class command. The user triggers updates by
running `/usr/local/sbin/update` inside the LXC — no wrapper path, no
re-downloading the CT script.

For addons, the naming follows the same convention:
`/usr/local/sbin/update_<slug>` and `/usr/local/sbin/uninstall_<slug>`,
with the same lifecycle rules (update persists, uninstall self-destructs).

There is no longer a legacy path through `/tmp/_update.sh` or
`/tmp/_uninstall.sh` — the temporary wrapper files have been removed.

#### 4.1.8 Post-install hooks: `complete_install`

After `build_container` returns, the shim calls `complete_install`.
This function owns the finalization stage of the install path.

In order:

1. Query the container for its IP address (via `pct exec`), storing it
   in a global that user hooks can reference.
2. Set the container's description text in the Proxmox web UI (for
   visual identification).
3. Invoke the user's `post_install_script` — by convention this hook
   prints access URLs and credentials.
4. Print the final success message (`msg_ok "Completed Successfully!"`).

`post_install_script` is the only user hook from inside this function.
The shim never calls it directly.

### 4.2 Addon install path

Single-context path — everything runs inside the existing container:

```
addon script begins
  declares APP, var_addon_* config, hooks
  curl-ensure block (per-script transport preamble)

source bootstrap/addon_lxc
  source install.func → _bootstrap runs:
    curl fallback ensure → source core.func, error_handler.func
    load_functions, catch_errors, get_lxc_ip, detect_os
  source tools.func, github.func, addon_lxc.func
  load check (addon_guard defined)

addon_guard
  → /proc/1/environ must contain container=lxc, else exit 1

addon_init
  → APP_SLUG = normalized APP (lowercase, spaces→dashes)
  → restore script header_info, render_header

addon_dispatch
  → addon_guard_installed
      marker /var/lib/scripts-underground/addons/<slug> absent → return 1
      marker present → prompt [u]pdate/[x]uninstall/[a]bort
        (ADDON_ACTION env bypasses; non-interactive stdin aborts safely)
        u → exec /usr/local/sbin/update_<slug>
        x → exec /usr/local/sbin/uninstall_<slug>
        a → exit 0
  → addon_run_install
      execute_mandatory_hook install_script     ◀ USER HOOK
      execute_optional_hook post_install_script ◀ USER HOOK
      addon_assemble_bundles
        fetch core/error_handler/install/tools/github .func to stage dir
        compose update bundle    → /usr/local/sbin/update_<slug>
        compose uninstall bundle → /usr/local/sbin/uninstall_<slug>
        alias both into /usr/bin (update-<slug>, uninstall-<slug>)
      addon_marker_write   ← LAST: any earlier failure leaves no marker,
                              so a re-run retries the install path
```

Failure semantics: with `catch_errors` active (`set -Ee -o pipefail`), any
unhandled error aborts before the marker write. The already-installed guard
keyed on the marker therefore never routes to half-built bundles after a
failed install.


### 4.3 PVE install path

**TBD** — see migration plan.

### 4.4 VM install path

**TBD** — see migration plan.

## 5. Variable propagation

### 5.1 LXC

#### Script-level variables

Every CT script declares resource defaults with the pattern
`var_cpu="${var_cpu:-4}"`. This is the contract between the script author
and the framework: any value that the framework may need to read uses
`${VAR:-default}` so callers can override it via the install one-liner or
the shell environment. Values outside this convention — private helper
variables like `DEFAULT_PORT` and `SRC_URL` — are the script author's own
concern and the framework ignores them.

The framework reads these variables during the `variables()` call. The
names that follow the `var_*` convention are consumed for container
creation (CPU, RAM, disk, OS type, version), PVE description (tags),
and the install wrapper. What the framework does internally with each
variable is the framework's concern; the script author's only obligation
is to declare them correctly.

#### Framework normalization

The `variables()` call transforms the user-declared values into
identifiers that the framework uses across stages. The most important is
`NSAPP` — a normalized form of the application name (lowercase, no
spaces, e.g. `APP="AFFiNE"` → `NSAPP="affine"`). This naming is applied
to the container's hostname and the pre-staged wrapper filenames.

Other derived values include `SESSION_ID` (an 8-character random session
identifier used for temp filenames and the failure flag file) and
`var_install` (the install wrapper name, computed as `${NSAPP}-install`).

These identifiers are computed once from the user-declared values at the
beginning of `variables()` and shared globally across the framework for
the rest of the install path.

#### Host-to-bundle transfer

All values that the container needs are baked into the bundle at
composition time on the host:

- **Framework libraries** — the full text of `core.func`,
  `error_handler.func`, `install.func`, and `tools.func` is inlined
  verbatim into the bundle. No re-fetch occurs inside the container.

- **Hook functions** — extracted via `declare -f <hook>` and appended
  as literal function definitions.

- **Host-derived values** — any `$REPO_BASE` reference used by the
  hook or install pipeline is expanded to its literal URL at bundle
  composition time. The container never needs to resolve the variable.

The bundle is fully self-contained once it leaves the host. The old
split (bake-in vs. re-curl) is eliminated — everything is baked in.

#### In-container environment

When `install_script()` runs inside the LXC, it executes inside a bash
process that has already sourced all 4 inlined framework libraries (the
bundle's preamble). All standard helpers are available: `$STD`,
`msg_info`, `msg_ok`, `msg_error`, `catch_errors`, `color`, and more.

State flows back to the host via the failure-flag file convention.
If an error occurs inside the container during the install, the bundle
writes `/root/.install-${SESSION_ID}.failed`. The host checks for this
file after `lxc-attach` returns and treats its presence as definitive
failure regardless of the attach's exit code.

The install bundle self-destructs on any exit (success or failure) via
`trap 'rm -f "${BASH_SOURCE[0]}"' EXIT`, so no host-side cleanup is
needed for the install artifact.

### 5.2 Addon

#### Script-level variables

- **`APP`** — required; `addon_init` derives `APP_SLUG` from it (lowercase,
  spaces to dashes) for bundle/marker naming.
- **`var_addon_*`** — bundle-consumed configuration. Declared as
  `var_addon_x="${var_addon_x:-default}"` so values are overridable from the
  environment AND baked into the update/uninstall bundles. The whole set is
  captured at install time via `compgen -v var_addon_`.
- **Plain globals** — install-time cross-hook state (e.g. a chosen port set
  by `install_script` and printed by `post_install_script`). Both hooks run
  in the same shell, so ordinary globals suffice; they are NOT baked into
  bundles.
- No `var_cpu`/`var_ram`/`var_disk`/`var_os`/`var_version` — addons don't
  size containers.

#### Framework-provided state

`detect_os` (run by install.func's `_bootstrap` at source time) provides
`OS_TYPE`/`OS_FAMILY`/`OS_VERSION`/`PKG_MANAGER`/`INIT_SYSTEM`; `get_lxc_ip`
provides `LOCAL_IP`. Scripts branch on `OS_FAMILY`/`INIT_SYSTEM` instead of
re-implementing OS detection.

#### Bundle baking

Each bundle carries, after its `set -euo pipefail` + PATH header:

1. **Context block** — `declare -- APP=…`, `APP_SLUG=…`, `REPO_BASE=…` and
   every `var_addon_*` variable, emitted with `printf %q` (same pattern as
   the LXC `build_bundle`).
2. **Framework libraries** — all 5 `.func` files inlined verbatim. The
   embedded install.func `_bootstrap` re-runs at bundle execution; its
   re-source of core/error_handler uses process substitution, which silently
   no-ops offline — so bundles remain fully functional without network.
3. **Hook body** — `declare -f <hook>`. Only the named function is copied:
   hooks must be self-contained (framework helpers OK, script-local helpers
   are NOT available).

Uninstall bundles additionally remove: themselves (resolving the
`/usr/bin/<alias>` symlink via `readlink -f`), the sibling update bundle,
both `/usr/bin` aliases, the install marker, and the now-empty marker
directories.


### 5.3 PVE

**TBD**

### 5.4 VM

**TBD**

## 6. Extension points

### 6.1 LXC

Three seams exist for extending the LXC install path. Each answers "if I
need to add something that doesn't fit, where do I look?"

**Adding a lifecycle stage.** When the install path needs a new phase
that doesn't fit into existing stages — for example, host-side
configuration after the container is created but before `complete_install`
runs. The seam is the shim: a new framework function call goes into
`bootstrap/lxc` and the function itself is added to `build.func`. The new
function must follow the same pattern as existing stage functions (it
receives global state and may invoke user hooks).

**Adding a user hook.** When a maintainer wants script authors to be
able to define custom behavior at a specific lifecycle point. The hook
is invoked by the framework function that owns the stage where the hook
fires — never by the shim directly. The framework function's
documentation and `function-reference.md` list available hooks and where
they fire. Adding a new hook means adding an invocation inside the
owning framework function and documenting it in `function-reference.md`.

**Modifying the in-container experience.** When every install needs to
include a new step inside the container — for example, a new setup
routine that runs before `install_script` or a new cleanup task after.
The seam is the pipeline argument passed to `build_bundle install ...`
in `build_container()`. Adding a step to that argument list applies it to
all LXC installs. The underlying bundle assembler (`misc/bundle.func`)
handles inlining and transport — no changes needed there.

For a catalog of existing framework helpers and their file locations,
see `function-reference.md`.

### 6.2 Addon

**Adding a user hook.** Add the invocation inside the owning framework
function in `misc/addon_lxc.func` (`addon_run_install` for install-path hooks,
`_addon_bundle_write` for bundle-embedded hooks) and document it in
`function-reference.md`. The shim never calls hooks directly.

**Modifying lifecycle behavior for all addons** (e.g. a new guard, a
pre-install check). The seam is `addon_dispatch` / `addon_run_install` in
`addon_lxc.func`.

**Modifying bundle composition** (new baked variables, extra inlined files,
different self-destruct behavior). The seam is `_addon_bundle_write` in
`addon_lxc.func`. Note the parallel with `build_bundle` in `bundle.func` — keep
the context-block conventions (`printf %q`, `compgen -v var_<type>_`) in
sync across both.


### 6.3 PVE

**TBD**

### 6.4 VM

**TBD**

## 7. References

- `misc/bootstrap/lxc` — LXC entry-point shim
- `misc/bootstrap/addon_lxc` — Addon entry-point shim
- `misc/bootstrap/pve` — PVE entry-point shim
- `misc/bootstrap/vm` — VM entry-point shim
- `misc/bundle.func` — Self-contained bundle assembler (`build_bundle`, `_framework_cache_ensure`)
- `misc/build.func` — LXC framework (orchestration, container creation)
- `misc/core.func` — common helpers (`msg_info`, `$STD`, `color`)
- `misc/install.func` — in-container install helpers
- `misc/tools.func` — app helpers (`fetch_and_deploy_gh_release`, `setup_*`)
- `misc/error_handler.func` — error traps
- `misc/vm.func` — VM-specific helpers
- `research/ProxmoxVED/misc/` — upstream reference
- `AGENTS.md` — contributor conventions (hook order, metadata format)
- `migration.md` — migration plan for code deltas
- `docs/script-ast.md` — AST parsing of scripts (token emission, hook
  detection, safety classification). Drives source rendering and the
  Jekyll plugin's per-page warnings.
