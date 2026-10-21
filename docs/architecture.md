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

Update bundles and `lxc_setup` run `update_script` through `run_update_script`
(core.func): `update` or `update --clean`, other options exit 65. A flag in
`/var/lib/scripts-underground/update-pending/<app>` is written before the hook and
removed only when the run exits 0. If the flag already exists, or `--clean` is
given, the run sets `UPDATE_FORCE=1 FORCE_DEPLOY=1`: release checks report
"due" and the current version is redeployed through the app's normal path.

`run_update_script` marks successful-update cleanup as due before entering the
hook. The framework's `on_exit` owns that cleanup for both a normal hook return
and an explicit successful `exit`. It captures the original exit status, removes
its own EXIT trap, clears the cleanup-due flag before calling cleanup, and runs
noncritical cleanup in a subshell so a cleanup failure or explicit exit cannot
replace the update status or recurse. Failed hooks skip cleanup and retain their
pending flag; successful hooks clear it even when noncritical cleanup fails.
Success includes a no-op update that finds no newer release and exits 0. It still
runs the approved package/cache cleanup (including the package manager's
autoremove where applicable); absence of deployment does not reclassify success.
The single `cleanup_lxc` implementation is in `core.func`, using `pkg_clean`
when supplied by `install.func`, then the existing language-cache cleanup.
It never sweeps `tmp*`/`tempfile*` names from TMPDIR or shared temporary contents:
a directory selection does not establish file ownership. Bundle/API owners remove
their own exact stages at their lifecycle boundaries instead.
An existing hook that calls this public helper explicitly acknowledges the same
due cleanup, so its later successful exit does not repeat package/cache work.

`silent` is a returning same-shell command wrapper. Quiet command output goes to
the active log, and its exact status is available to `if`/`||` retry branches.
Unhandled failures still reach the framework ERR/errexit boundary. It scopes
`set` options with Bash `local -`, restores the caller's ERR trap (including an
absent trap), and does not disable the command's pipefail setting. Ordinary
variable/cwd/umask effects remain in the caller. This uses normal Bash conditional
semantics: functions must propagate intermediate failures themselves, and an
explicit `exit` or signal is not converted into a return. Verbose `$STD` remains
the existing empty-command passthrough; no telemetry/error-context global is added.
Consumers must not use an unchecked `$STD required_step && next_step` as fatal
sequencing: Bash suppresses ERR/errexit for the left side of `&&` in both modes.
Use ordinary sequential commands for required work, or explicit checked returns
when a consumer is intentionally conditional. Uninstall owners call hooks normally.
Intentional conditions, retries and best-effort `||` handling retain Bash semantics.

Each bundle carries its own **runtime context**, baked at build time from the
host shell: `APP`, `NSAPP`, `REPO_BASE`, and any `var_lxc_*` variables the
script has declared. Hooks may reference these directly. The context block
appears after `set -euo pipefail` and before the inlined framework files.

GPU context is also baked into every LXC bundle: `ENABLE_GPU`, `GPU_TYPE`
(a space-separated list of selected vendors), `INSTALL_NVIDIA_DRIVERS`, and
`CTTYPE`. Host passthrough classifies each DRM node by its sysfs vendor, includes
AMD's `/dev/kfd` when present, and offers multi-vendor and per-NVIDIA-card selection
(default/unattended: all). New mappings are deduplicated against existing entries,
and `devN` numbering continues after the highest existing index. `fix_gpu_gids` owns node
attributes through `pct set`, using container video/render GIDs with 44/104
fallbacks; failures warn. Guest permission setup only adds group membership and
does not chmod/chgrp mapped host devices.

Inside the container, `setup_hwaccel` uses mapped character nodes and DRM sysfs
vendors, filtered by the baked `GPU_TYPE`; PCI lookup only identifies the mapped
Intel GPU's subtype. It exports available userspace stacks in `HWACCEL_VENDORS`
and the preferred stack in `HWACCEL_VENDOR` (NVIDIA, AMD, Intel, otherwise none).
NVIDIA usability requires libcuda and any mapped NVIDIA node. A non-empty
`INSTALL_NVIDIA_DRIVERS` supplies the install choice; otherwise the existing
60-second prompt defaults to yes on empty input, timeout or EOF. Libraries are
installed when the resolved choice is `yes`. Optional GPU package/release
steps log directly to the active log and warn on failure rather than using
`silent()`. Intel OpenCL uses the IGC tag in compute-runtime's release
notes, never an unrelated latest IGC. AMD ROCm is only set up with mapped `/dev/kfd`.

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
   → pct push wrappers ─────────────────────→ receiving temporary root
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
   - **Install bundle** (default `/tmp/install-bundle.sh`): inlines all 5
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

Creator-side staging, pulled/capture logs and framework-cache allocation use
`${TMPDIR:-/tmp}`. The cache owner computes one root/session path for both its
fetch and later inlining reads; changing TMPDIR does not reuse another root's
bytes. Each sender bundle and addon staging directory is privately allocated,
and cleanup removes only that owned staging artifact.

Creator and receiver temporary roots are different filesystem contexts. LXC
bundles still discard inherited creator TMPDIR. An explicit `var_lxc_tmpdir`
uses the existing baked `var_lxc_*` context to select the receiving root before
framework initialization. `build_container` creates that root when selected and
uses the same install-bundle path for push and execution, including the in-place
retry. The explicit value must be an absolute, non-root normalized path: no empty
components, trailing slash, dot/dot-dot components or newline/carriage-return/tab.
Spaces are supported. `_validate_lxc_tmpdir` checks this lexical contract without
inspecting the creator's filesystem. `_prepare_lxc_tmpdir` walks components using
Bash builtins and rejects existing or dangling symlink components before any
creation, without requiring GNU `realpath -m` on Alpine. It creates missing
receiving intermediate directories with mode0755 and only the selected leaf with
conventional shared sticky mode01777. An app user can create leaf tempfiles but
cannot replace a removed leaf through a writable new parent. Preparation preserves
every existing directory's metadata. Existing selected paths must already let
the intended app users traverse/write them; preparation does not chmod user paths.
The same helpers run remotely before installer publication and in every generated
install/update/uninstall prelude, before any library source-time effects or logs.
This recreates an explicit temporary directory removed between invocations.
Invalid values exit65 before receiving effects; creation failures retain their
native status. With no override the receiving default remains `/tmp` and creator
TMPDIR is discarded without introducing a new inherited-environment policy.

`_prepare_container_bundles` explicitly checks root preparation, every bundle and
the command aliases for both initial creation and repair. Initial preparation
retains normal framework error handling. After the user chooses in-place repair,
a preparation failure reports its exact status and exits preserving that existing
container, without stale execution or re-entering the host's timed removal prompt.
Only container execution is placed in the status-capture section. Addons stage
within their current container's selected TMPDIR.

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
    `core.func`, `error_handler.func`, `install.func`, `tools.func`, `github.func` are
   fetched from `$REPO_BASE` and verified (size > 100 bytes, sentinel
   functions present).

2. **Inline everything into a single script**:
    - Shebang, `set -euo pipefail`, minimal PATH and receiving temporary context
    - Baked app/`var_lxc_*` context using `printf %q`
    - All 5 framework `.func` files, verbatim, between `# ═══` markers
   - Sanity checks that the expected sentinel functions loaded
   - `load_functions`, `catch_errors`, `color`
   - `declare -f <hook>` — the function body extracted via `declare -f`
   - Role-specific pipeline and footer:
     - **Install**: `trap 'rm -f "${BASH_SOURCE[0]}"' EXIT` +
       `setting_up_container`, `network_check`, `update_os`,
       `install_script`, `motd_ssh`, `setup_lxc`, `cleanup_lxc`
     - **Update**: `run_update_script "$@"` (calls `update_script`) — no self-destruct
      - **Uninstall**: normal `uninstall_script` call under existing ERR/EXIT
        handling, then success-only removal of commands/markers

3. **Push into the container** via `pct push` and set the execution mode.

The builder owns its private sender artifact. `_write_bundle` checks every
producer operation explicitly (including each library read, context write and hook
definition), even if the public builder is called in an `if`/`||` context.
Any writer failure returns its original status, removes that owned artifact and
prevents publication. No compound-block errexit assumption or new trap owner is
used. Successful publication and push/chmod failures also remove the sender file.
The LXC receiver also allocates an owned same-filesystem stage: push writes there,
mode is checked there, and atomic rename publishes the complete command. Failed
partial transport, mode-setting or rename preserves the previous receiving bundle
and removes the owned receiver stage. Persistent aliases are checked before their
corresponding bundle publication. This is per-command publication, not a transaction
across the install/update/uninstall set.

No network I/O happens inside the container for framework loading — all
libraries are already part of the bundle file. Each bundle is fully
self-contained once it leaves the host.
`install.func`'s bootstrap checks the existing `load_functions`/`catch_errors`
APIs and fetches only missing libraries. Connected and offline bundles therefore
retain the same inlined error/cleanup generation instead of replacing it with
the currently published library while loading.

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
| Install | `${var_lxc_tmpdir:-/tmp}/install-bundle.sh` | Self-destructs on EXIT (success or failure) |
| Update | `/usr/local/sbin/update` | Persists — user runs it directly |
| Uninstall | `/usr/local/sbin/uninstall` | Self-destructs on successful uninstall |

The update bundle is a first-class command. The user triggers updates by
running `/usr/local/sbin/update` inside the LXC — no wrapper path, no
re-downloading the CT script.

For addons, the naming follows the same convention:
`/usr/local/sbin/update_<slug>` and `/usr/local/sbin/uninstall_<slug>`,
with the same lifecycle rules (update persists, uninstall self-destructs).
Both LXC and addon uninstall bundles preserve a nonzero hook return and retain
their command/marker on failure; they self-destruct only after a successful hook.
The hook call is never an `if`/`||` condition: Bash would disable errexit for its
entire body, allowing a failed ordinary `$STD` command to reach data deletion.
The existing `error_handler` supplies the fatal status, diagnostics and owned
spinner stop for failures, including an explicit nonzero hook return. Addon
installed dispatch uses `exec` into that normal bundle path.

Service-managing uninstall hooks use `svc_prepare_uninstall` from the existing
init abstraction. It is uninstall-specific; install/update `svc_stop`,
`svc_disable` and sibling semantics are unchanged. Checked systemd properties or
a completed OpenRC service list/state query establish presence before control.
Only verified absence/stopped/disabled states skip work. Query and stop/disable
failures keep their exact status, emit diagnostics and reach the plain hook's
existing error boundary before app/unit/config removal. OpenRC queries all verified
runlevel registrations and removes each before init-file deletion; query or control
failure is not absence. A systemd not-found inactive/failed tombstone is safe; a
not-found active unit still needs a checked stop. Known broken load or empty/bad
unit-file states do not replace the actual control outcome. Missing properties,
unknown/malformed states and failed queries fail closed. All helper locals use the
reserved `_svc_` prefix so caller outputs such as `state` remain caller-owned.
The `stop` action retains shared service
enablement, with an optional caller-owned prior-running output for Apache.
phpMyAdmin restores a previously running shared Apache before app deletion; it
does not start an absent/stopped shared server. Its dedicated Alpine Lighttpd is
stopped/disabled before removing the app configuration; shared PHP-FPM stays up.
Netvisor returns normally so successful command/marker cleanup remains owner-run.

New builds no longer stage legacy `_update.sh`/`_uninstall.sh` wrappers; they
push the persistent bundles directly. `setup_lxc` retains its compatibility
reader for such files in the selected receiving temporary root.

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
process that has already sourced all 5 inlined framework libraries (the
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
2. **Framework libraries** — all 6 `.func` files inlined verbatim. The
   embedded install.func `_bootstrap` re-runs at bundle execution, initializes
   the already inlined core/error APIs and fetches only missing libraries.
   It therefore keeps the frozen generation both online and offline.
3. **Hook body** — `declare -f <hook>`. Only the named function is copied:
   hooks must be self-contained (framework helpers OK, script-local helpers
   are NOT available).

Uninstall bundles additionally remove: themselves (resolving the
`/usr/bin/<alias>` symlink via `readlink -f`), the sibling update bundle,
both `/usr/bin` aliases, the install marker, and the now-empty marker
directories.

Addon serialization follows the same explicit checked-producer contract as LXC.
`_addon_bundle_contents` checks every producer even under conditional callers;
`_addon_bundle_write` owns a private same-filesystem stage, checks mode and alias,
and atomically renames completed bytes over the command. Generation, write,
chmod, alias or rename failures preserve the previous valid bundle and exact
status, removing the owned stage. The fetch-stage owner similarly removes its
own directory and propagates failures. No live-file truncation, shared temp sweep,
new trap owner or multi-artifact transaction engine is involved.


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

## 7. Shared runtime and release maintenance

Runtime and provider changes stay in the existing `tools.func` public helpers.
`setup_nodejs` establishes its safe `/opt` cwd before legacy cleanup or any npm
work, and refreshes the NodeSource signing key before same-major apt metadata/
upgrade work. Key refresh remains a reported noncritical failure; configured
Node/module versions and existing npm/pnpm pins are not globally changed.
`download_gpg_key` downloads privately, processes and validates with GPG in an
owned same-filesystem stage, then atomically publishes. All modes preserve the
last-known-good key on transfer, processing, validation or publication failure.
Existing key mode/owner are retained; fresh keyrings use0644 for apt readability.

`_uv_required_spec(dir)` owns the configuration read for both exact and range
consumers: root `uv.toml` first (even when it masks a pyproject requirement), else
`[tool.uv]` in `pyproject.toml`. Quotes, sections, comments and the legacy bare
exact value remain supported. Status1 means no requirement,65 a malformed one.
`_uv_required_version(dir)` remains the exact-pin compatibility wrapper; a range
still returns1 through that interface. `setup_uv` selects explicit UV_VERSION,
then the project requirement, then latest only when no requirement exists.

Ranges support comma-separated AND clauses `==`, `!=`, `<`, `<=`, `>`, `>=`, `~=`
with numeric bounds. Compatible-release upper bounds follow the supplied precision
(`~=0.12.15` is below0.13; `~=0.12` is below1). The release-list request is completed
and JSON-checked across all release-list pages, filters draft/prerelease/nonstable
tags and version-sorts the complete result. Unsupported syntax, a failed page and
no satisfying stable release fail rather than installing incompatible latest. Exact
pins and explicit overrides do not require range enumeration.

GitHub version lookup, checking and deployment share a small request/selection
boundary, not a cross-forge coordinator. Completed curl status and JSON shape are
checked before selection. HTTP status is a named output so token recovery stays
in the caller for subsequent asset downloads; diagnostics never enter JSON output.
An unfiltered latest request honors the designated `/latest` object; an optional
stable tag-prefix selects from the release list. Prefix means raw `startswith`,
not numeric/component matching: include the actual leading `v` and the desired
separator (`v1.2.` excludes `v1.20.0`, whereas `v1.2` matches both). Pins retain priority and raw tags
are preserved; one numeric-v compatibility helper handles comparisons and markers
without stripping the leading character from word tags or adopting mangled markers. A requested
release never falls back to another release's asset; latest asset fallback stays
within the selected prefix. Existing own-marker, force and checked-copy behavior
is retained.
One private list owner handles complete pagination for uv and prefix selection.
It checks every page, refuses repeated-page/nonprogress responses and
publishes a list only after completion. A prefix cannot infer published/stable
release state from Git tags if that release list is unavailable.
Unfiltered latest lookup retains semver Git-tag fallback when no stable release
exists, including a successful empty/prerelease-only list. Malformed/incomplete
producers are errors. Older-asset lookup separately retains one checked request
bounded to the original15 releases, returning the first compatible match in API
order; it never paginates into ancient history. Request diagnostics stay on stderr
and provide safe authentication/rate-limit hints. The public checker ends its
owned spinner on failure, including failures before an HTTP request.

`check_for_gh_release(app, repo, pin, reason, prefix)` adds only the optional fifth
argument. `fetch_and_deploy_gh_release(app, repo, mode, version, target, asset,
prefix, selected_json_file)` adds optional seventh/eighth arguments. Its eighth
argument is a caller-owned output file: cleared at call start and written with
the actually selected release object on success, including no-op success and
older-asset fallback. Internal response files/stages are private and removed by
their owners. No global temporary metadata file or exported last-response state
is used.

Intel metadata consumers allocate their own file, pass it through the existing
optional-command subshell, call `_resolve_igc_tag(outvar, selected_json_file)` and
remove that file. Jellyfin uses the same explicit transport. This changes metadata
association, not package ordering, device eligibility, optional-failure or GPU
hardware policy. A later fetch for another repository cannot replace that call's
selected metadata.
Jellyfin's required update path refuses missing/unresolved compiler-pin metadata
with250 before requesting IGC, rather than letting an empty pin imply latest.
The optional Arc/modern paths retain their existing missing-pin skip behavior.

`get_system_arch(source, amd64_alias, arm64_alias)` retains its dpkg default and
existing normalized uname/both modes. Explicit second/third arguments map release
asset aliases, e.g. `get_system_arch both x64 aarch64`; no global architecture
rename or application default change is implied.

### Checked replacement and application persistence

`_deploy_replace_contents` is the shared source/archive replacement owner for
GitHub tags/releases, Codeberg tags/releases, GitLab releases and URL archives.
The URL route also extracts and checks before any live replacement. Existing
`CLEAN_INSTALL_KEEP` paths are protected against both cleanup and incoming source
defaults, in clean and merge modes. Its legacy space-separated string remains
unchanged. The optional indexed Bash array `CLEAN_INSTALL_KEEP_PATHS` adds literal
paths losslessly, including whitespace, alongside that string. Both require
normalized relative paths; absolute/root/dot/dot-dot/empty components, trailing
slashes and wildcard paths fail65 before effects. Legacy string control separators
also fail65; array elements are never word-split. Missing paths can receive source
defaults. Symlink ancestors protect the link itself.

A private source-only projection uses archive hardlinks when supported, independent
directories and checked full-copy fallback after removing owned partial links.
Existing merge directories and dot-merge branches stay in place: only incoming
replaced leaves and genuinely new directories are published in bounded argv
batches with associative membership. Old-only live contents are never projected,
copied, moved or traversed. Clean removal descends only persistent/mount ancestor
spines. Kept paths, links and
mounts never move, copy out/back or receive archive default bytes/metadata. Linux
mountinfo identifies nested/same-device bind mounts without walking their data.
Incompatible merge directory/file/link types fail252 before live replacement;
ordinary payload data never follows a destination symlink into user data.
The existing same-filesystem aside contains only replaceable siblings; failed
publication removes attempted planned leaves and only empty planned directories,
retains unrelated concurrent entries, and restores prior entries around them.
Restore batches require absent destination names, never overwrite/nest around a
conflicting writer, and verify no-clobber moves actually moved each old entry.
Fresh decoded mountinfo containment guards every owned recursive tree removal;
a new nested mount retains/reports the stage/aside instead of traversing it.
There is no new-sibling sweep. An incomplete restore is an error
with its recovery location retained. Source inputs and target-root mode/owner
are unchanged. This extends the checked helper, not a transaction/journal engine.

CLIProxyAPI declares config.yaml/plugins/data, Sure storage, PrivateBin cfg/data,
and ByteStash current data. PrivateBin update leaves existing config/data metadata
alone and initializes ownership only when the data path was absent. Critical
CLIProxyAPI/PrivateBin config must exist rather than being silently reset. Legacy
ByteStash `/opt/data` lies outside the replacement root and is untouched; update
does not restore unrelated/stale backup data over it. Fresh ByteStash2CPU/2048MiB
defaults match pinned upstream and catalogue metadata; existing resource/settings
overrides and installed service units are not rewritten.

### Bounded application source/startup compatibility

OneDev install/update uses the current ~sites/public distribution URL. The extracted
root release.properties version must match the selected/requested release before
upgrade, and installed metadata must still agree before own-marker publication.
The mutable latest archive is never silently relabeled as GitHub's selected tag.
Both installed legacy onedev and
current onedev.server units are supported; after an app-owned upgrade, service
selection reflects the unit that remains. Failed downloads/upgrades do not start
the service or advance the own marker.

Apprise copies the static directory's contents into the documented /s document
root on install and update, including when that root already exists. Its bounded
HTTP fixture proof verifies actual upstream CSS bytes and changed revision bytes
at the consumer URL; it is not a full Apprise/Nginx/Django installation proof.

Pelican supplies explicit noninteractive environment setup URLs. Update preserves
the existing .env/uploads/plugins/SQLite paths through checked replacement, then
uses the application's Dotenv dependency to decode the existing APP_URL. SQLite
journal/WAL/SHM siblings, including whitespace-named files, are added losslessly to
the local inherited keep-path array and retained through failure and pending retry.
Matching
outer quotes are parsed without deleting embedded apostrophes; missing/invalid
settings are checked errors, never guessed defaults. Composer/Artisan migrations
remain application-owned. Wiki.js follows wiki-v2 and preserves config/data, with
SQLite database/sidecar preservation and rebuild conditional on an existing SQLite installation; the
fresh PostgreSQL default and existing runtime/database-major choices stay intact.

Sonarr's default checker/deployer select the v4 stable line and use the existing
architecture alias API for x64/arm64 assets. Explicit provider pins retain their
priority. Gluetun follows the canonical passteque repository in metadata/check/
deploy and asks the existing Go helper to read the selected source requirement;
explicit local Go versions override that optional project input. Project go and
toolchain directives are minimums: a satisfying installed stable version stays;
otherwise checked official release metadata selects the latest stable patch of
the required minor, including historical initial tags without .0. Failed metadata
or download leaves the previous runtime in place; other callers keep their
existing latest/explicit-version selection.

### Application-owned runtime/build inputs

App hooks consume metadata from the selected deployed source rather than a
different branch's text or an unrelated latest release. Their installed database
major, credentials, data paths and existing service options remain caller-owned.
Required build/migration errors retain the update-pending flag for a normal retry.

| Application | Selected-source contract |
|---|---|
| Radicale | Native TOML optional dependencies determine supported bcrypt/argon2 extras in both installation and deployed unit command. Native INI/unit parsing identifies configured in-tree credential/calendar paths before replacement. |
| Discourse | The saved environment, production Rails context and rbenv PATH apply to pnpm, database and asset commands. Both application and Sidekiq stop/start together. Nginx changes are validated and reverted on validation failure; updates do not provision a new PostgreSQL major. |
| ThingsBoard | Its Java25 source requirement applies to fresh/update paths. Package upgrade preserves existing configuration and database provisioning; the downloaded package is an owned temporary artifact. |
| AliasVault | The supported core `--web` target and React `apps/web` build replace the retired Blazor layout. Node24 consumes the current dependency graph; `apps/web/dist` publishes into the existing served `client/wwwroot`. Existing settings, certificates, secrets and data are protected before source/build work. |
| Tracearr | The selected packageManager and production server dependency closure include shared, emails and the runtime logo. A private runtime projection publishes through the checked helper; existing data, environment and prestart/database-major context remain in place. |
| Twenty | The registered application-owned `command:prod upgrade` runs with the existing environment. Upload storage and lossless inherited keep paths survive replacement and failures; the script does not invent an alternate migration sequence. |
| Kima-Hub | Both analyzers use an isolated Python3.11 environment and the source's compatible NumPy/ONNX/Essentia pins, without system pip or TensorFlow. Public model inputs/exports and the offline tokenizer cache retain upstream checksum gates; native MusiCNN/CLAP parity gates precede service startup. Existing user models and unit options remain intact. |
| Paperclip | The selected pnpm version first performs a frozen install. Only a completed status1 with exclusively exact structured `ERR_PNPM_OUTDATED_LOCKFILE` errors permits one unlocked retry. Native Node dotenv parsing protects custom home/config paths and supplies the saved migration environment; network/auth/build/malformed/mixed errors remain failures. |
| Paperless-ngx | Default v2.20.15 remains pinned. A read-only native Dotenv/JSON/source-version preflight runs before hook maintenance or service/source/config changes. Explicit v3 overrides convert only proven exact glob semantics; unrepresentable directory globs, absolute-root collisions and malformed/ambiguous provenance return65 with actionable diagnostics. |

Paperless format provenance is an app-owned comment in the existing config, not
separate transaction state. A glob-v2 comment records unchanged current values
before source replacement; regex values and regex-v3 provenance publish atomically
after the selected source is installed. Concurrent config edits are retained and
reported. Existing explicit regex intent stays byte-identical. The restart repair
reads base units and drop-ins, adds only missing defaults and preserves independent
user `Restart`/`RestartSec` directives, including same-version repair.

The focused cold-hook tests execute actual helpers/files and native parser/module
consumers with explicitly modeled compilers, model weights, database provisioning
and service control. A bounded Node24/Vite compiler fixture verifies generated
HTML/JavaScript and all lock-listed Node engine constraints; it does not stand in
for a complete AliasVault Rust/.NET/React installation. Wheel import evidence
likewise does not prove neural inference or full Kima operation.

### Privacy, backups and pinned CPU build callers

Webtrees stages a Caddyfile candidate, preserving existing custom configuration,
then uses native `caddy validate` and the adapted route graph before publication
or reload. The private-path403 guard must precede serving/rewrite handlers. A
failed validation or unproven custom routing retains original bytes; a concurrent
edit is reported instead of overwritten. Privacy repair runs even when the app
release is unchanged. Its data directory stays live through checked replacement.

Zigbee2MQTT streams tar stdout directly into zstd; only the compressor is wrapped
by STD. Each archive has an exclusively allocated filename, including repeated
same-version operations. The completed pipefail status is captured before removing
the owned partial archive, and failure never advances to deployment. Existing
settings/coordinator data stay in place through source replacement and failures.

Immich's default release is app-local `var_lxc_release` (v3.3.1); an explicit
requested release retains priority. Fresh/update build the same selected source.
That source's Dockerfile selects the base-images tag and CPU interpreter, and its
packageManager/mise metadata selects build tools. The six pinned base-image library
recipes run from a private source stage, with revision records published after
success. Update's hook contains its own library compiler definition; unrelated
script-global functions are not assumed to cross the bundle boundary. An Immich
pin is explicitly masked for independent VectorChord selection.

Updated app artifacts are privately built and published through checked replacement.
The app build stage is allocated beside the persistent live application under
`/opt/immich`, independently of a potentially RAM-backed production TMPDIR.
The app publication call also scopes TMPDIR to that install disk, so the shared
helper's projection can hardlink the large input instead of falling back to a
cross-filesystem copy into global scratch. The caller owns exactly its allocated
app stage: a cold-contained checked build/publication function returns every
required failure, then the caller leaves the stage and attempts its checked
cleanup on both success and failure. The original build/publication status wins
if cleanup also fails; successful work cannot hide a cleanup failure. Unknown
prior app stages are never swept or reused.
ML dependency synchronization still operates in the existing installed venv. The
app-artifact publication proof does not establish ML-environment atomic rollback;
failed ML operations remain fatal and retryable through the pending-update owner.
Native environment parsing protects configured data in either the source or app
root, plus the existing upload link/runtime and inherited literal keeps. Existing
environment/database-major choices remain intact. Geodata repair targets the actual
geodata directory and uses an exact symlink destination, including same-version
repair. Optional source-pattern rewrites distinguish grep's no-match1 from genuine
producer errors and pass filenames losslessly. Python/ML/plugin-tool retries have
explicit exact-status exhaustion boundaries; Frigate's wheel caller does likewise.
No successful build message or later stage follows exhausted retries.

The focused proofs distinguish native Caddy HTTP, tar/zstd streams, filesystem
preservation and selected-source geodata readers from modeled application/image
library compilers, database/service operations and ML environments. These outcomes
do not establish full Immich operation or postponed GPU/model functionality.

Forgejo fresh HTTP defaults use port80 without running the application as root.
The Debian installer follows the documented login-capable `git` account with a
fresh `/home/git` home, reuses an existing account/home, keeps executable code
root-owned and grants only the service's bind capability. Existing service/home/
SSH/config/data/port settings are not regenerated by the updater.
The new Debian unit does not impose NoNewPrivileges, which would also restrict
legitimate setgid helpers. Native onboarding/SSH proof does not establish mail
delivery behavior. Alpine retains
the distribution's `forgejo` account, home and OpenRC contract. A new package
configuration gets port80; an existing configuration is retained. File capabilities
already configured before package replacement are restored afterward, rather than
granting new capabilities to an existing high-port/no-cap installation.

Native Forgejo acceptance is a distinct owned-CT gate: actual web onboarding on
port80, repository SSH clone/push and an independent consuming clone, followed by
real update preservation with custom account home, SSH keys, repository/data paths
and port. Source/callback fixtures, version output and service startup are not
substitutes. Native template/package/rootfs/temporary-peak accounting must admit
each variant before creation/download; a blocked variant stays explicitly unverified.

## 8. References

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
