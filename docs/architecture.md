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
  container and wants to install something into it). Different bootstrap,
  different dispatch pattern (MODE env var drives install/update/uninstall).

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
| `install_script` | `build_container` | Container, via wrapper |
| `post_build_script` | `build_container` | Host, after install completes |
| `post_install_script` | `complete_install` | Host, as final step |
| `update_script` | `start` | Container, on re-run |
| `uninstall_script` | — | Container, via pre-staged `/tmp/_uninstall.sh` |

#### Hooks NOT invoked by the shim

`update_script` and `uninstall_script` are not part of the install path.
They are invoked from inside the container later (update via re-running
the CT script or running `/tmp/_update.sh`; uninstall via
`/tmp/_uninstall.sh`).

`header_info` is not a lifecycle hook — it's a display hook invoked by
`render_header()` early in the bootstrap (after `color` / `vm_init_colors`,
before `catch_errors`). If the script defines `header_info()`, the
framework's `render_header()` dispatches to it; otherwise a generic
fallback (`header_info_fallback()`) displays the app name.

### 3.2 Addon — `misc/bootstrap/addon`

**TBD** — see migration plan.

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
6. Compose the install wrapper and the update/uninstall wrappers.
7. Push all wrappers into the container via `pct push`.
8. Execute the install wrapper via `lxc-attach`.
9. Check the failure flag that the wrapper writes on error.
10. Invoke the user's `post_build_script` on the host.

`pre_build_script` and `post_build_script` are the only user hooks
called from inside `build_container`.

#### 4.1.5 Wrapper composition

The user's `install_script` is a bash function defined in the host shell.
The framework needs that function to execute inside the new LXC, in a
different bash process spawned via `lxc-attach`. Bash function definitions
don't cross process boundaries — the framework must transport the function
body explicitly.

The transport mechanism uses `declare -f`. The framework calls
`declare -f install_script` in the host shell, which outputs the function
body as text. That text is appended to a wrapper script alongside two
other sections:

- A **fixed prelude** that asserts the script is inside an LXC and
  sources the framework files again (`core.func`, `tools.func`) so that
  helpers like `msg_info` and `$STD` are available inside the container.
- A **postamble** that calls setup/cleanup functions (`setting_up_container`,
  `network_check`, `update_os`, `motd_ssh`, `setup_lxc`, `cleanup_lxc`).

The complete wrapper is a self-contained bash file. The framework writes
it to a host temp file, pushes it into the container with `pct push`,
then executes it via `lxc-attach`. No env vars are needed to carry the
function — the function body is part of the file.

The same mechanism composes two additional wrappers for
`update_script` and `uninstall_script`.

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

#### 4.1.7 Pre-staging update and uninstall wrappers

While composing the install wrapper, the framework also composes wrappers
for `update_script` and `uninstall_script` using the same `declare -f`
mechanism. These are written to `/tmp/_update.sh` and
`/tmp/_uninstall.sh` inside the container. After install completes, they
remain there.

The user can trigger an update by running `bash /tmp/_update.sh` inside
the LXC. There is also a second path to update: re-running the CT script
inside the container. The framework's `start` function detects the
container context (no `pveversion`) and dispatches to update mode,
calling the user's `update_script` directly. The two paths are equivalent
in effect.

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

**TBD** — see migration plan.

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

#### Host-to-wrapper transfer

Two mechanisms carry values from the host environment into the running
container's install session.

The first mechanism bakes host-derived values directly into the wrapper
script text via the unquoted heredoc at composition time. When the host
composes `_install_wrapper.sh`, specific shell variables (`$SCRIPTS_URL`)
are expanded to their literal values at that moment, becoming part of the
wrapper file as static text.

The second mechanism re-acquires values from the network at container
runtime. The wrapper's prelude curls framework files (`core.func`,
`tools.func`) fresh inside the container, sourcing them to make helpers
available.

The split follows a clear rule: values that depend on the host's
environment at install time get baked in; values the container can
re-derive (framework helpers) get re-curled. Values are never smuggled
across the boundary via environment variables — the wrapper is fully
self-contained once it leaves the host.

#### In-container environment

When `install_script()` runs inside the LXC, it executes inside a bash
process that has already sourced the wrapper's prelude. The prelude has
curled `core.func` and `tools.func` and run their setup functions, so
all standard helpers are available: `$STD`, `msg_info`, `msg_ok`,
`msg_error`, `catch_errors`, `color`, and more.

The host-derived values that were baked into the wrapper during
composition are present in the wrapper file as literal strings. The
variable `$SCRIPTS_URL`, for example, was expanded at host time and
appears as a plain URL string inside the bash file — the container does
not need access to the original environment or `REPO_BASE` to know where
to curl framework files.

State flows back to the host via the failure-flag file convention.
If an error occurs inside the container during the install, the wrapper
writes `/root/.install-${SESSION_ID}.failed`. The host checks for this
file after `lxc-attach` returns and treats its presence as definitive
failure regardless of the attach's exit code.

### 5.2 Addon

**TBD**

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
The seam is the wrapper's boilerplate composition in `build.func`. The
wrapper's prelude and postamble are the sections that define what every
in-container install session includes. Adding a step there applies it to
all LXC installs.

For a catalog of existing framework helpers and their file locations,
see `function-reference.md`.

### 6.2 Addon

**TBD**

### 6.3 PVE

**TBD**

### 6.4 VM

**TBD**

## 7. References

- `misc/bootstrap/lxc` — LXC entry-point shim
- `misc/bootstrap/addon` — Addon entry-point shim
- `misc/bootstrap/pve` — PVE entry-point shim
- `misc/bootstrap/vm` — VM entry-point shim
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
