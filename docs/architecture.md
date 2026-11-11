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
ends with `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "appname" -- "$@"`,
where `appname` is the literal filename stem. This loads the framework and runs
the install path while preserving caller arguments.

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

The shim loads the framework and invokes its checked entry:

```bash
source <(curl -fsSL "${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}/misc/build.func") 2>/dev/null

declare -F _lxc_bootstrap >/dev/null || { printf 'FATAL: LXC bootstrap entry not loaded\n' >&2; exit 111; }
_lxc_bootstrap "$@"
```

Every line is `source`, a guard, or a framework function call. The shim invokes
no user hook directly. `_lxc_bootstrap` captures the optional producer tuple
`--script-id <id> --` into a local before defaults, then runs `variables`,
`color`, `render_header`, `catch_errors`, `lxc_setup`, `build_container` and
`complete_install` in order. Only remaining arguments reach `lxc_setup`.

- Line 1 sources `build.func`, which as a side effect pulls in
  `core.func` and `error_handler.func` and runs setup
  code (`load_functions`, `catch_errors`).

- The guard refuses an unavailable framework entry with 111.

- The entry sets up the framework's global state: normalized app
  identifiers, ANSI color vars, strict-mode error traps.

- `lxc_setup` dispatches by context. On the Proxmox host it runs
  the whiptail menu (via `setup_script`) to collect container settings.
  Inside an existing container it runs the update flow instead.
  If `start` returns, the install path continues.

- `build_container` creates the LXC, runs the app installer
  inside it, checks the result, fires `post_build_script`.

- `complete_install` queries the container for network info,
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
(core.func): `update` or `update --clean`, other options exit 65. The runner
acquires a fresh per-app maintenance owner before pending admission.
LXC preparation now runs the resource adapter after fresh ownership but before
pending/FORCE/hook/cleanup admission, including hooks that omit their own check.
Refusal or query failure preserves prior pending bytes and arms no cleanup. The
public LXC invocation owns a fresh non-exported four-value consent tuple; repeated
hook checks reuse only identical required CPU/RAM and freshly measured actual
CPU/RAM. Changed inputs or failed probes cannot reuse it. Independent invocations
and direct adapter calls outside that owner perform normal admission. Addon
literal baseline preparation remains separate; shared confirmation is stateless.
One stable
empty root-owned 0600 one-link inode lives under the private 0700
`/var/lib/scripts-underground/maintenance-locks`; its nonsymlink ancestors must be
root-owned and not group/world writable. Existing unsafe metadata is refused,
never repaired. Opening checks path/FD identity, using executable flock/stat/mkdir
rather than caller function models. No filesystem-type or findmnt dependency is
introduced. Canonical keys use the existing NSAPP/APP_SLUG: 1–64 ASCII lowercase
alphanumeric/dot/underscore/hyphen bytes, starting alphanumeric. Different keys
and CT filesystems remain independent.

`app_maintenance_acquire(key)` can acquire a direct owner or borrow the matching
validated FD in that owner's productive fork lineage. Owner state stays
non-exported, including under set-a; exported/imported values are discarded. An exec'd command
acquires independently. A different-key borrow or re-entering the terminal update
runner in the same lineage refuses 70. Bad keys return 65, unsafe/unavailable
infrastructure 69 and contention 75. Nonblocking `flock -n FD` supports util-linux
and compatible BusyBox applets; BusyBox's coarser native status 1 fails closed 75.
Missing executables fail before update effects, without package installation.
Diagnostics use builtin stderr output, avoiding another owner's shared spinner
PID file. Lock inodes are never unlinked, replaced or age-deleted.

The main update shell keeps its FD through hook subshells, app recovery and outer
EXIT cleanup/pending retirement. No second global EXIT trap or explicit unlock is
needed: the last kernel FD closure releases ownership. Productive children retain
it after launcher death until their work ends. Only msg_info's actual background
UI spawn closes the maintenance FD before spinner; foreground spinner calls and
productive work do not. PID 1-started services do not inherit the hook's descriptor.
A directly spawned persistent daemon that retains the descriptor keeps the app
lock until it exits; later independent updates then report 75.
This protocol covers participating generations only: drain old unguarded updaters
before deploying/refreshing frozen bundles. Framework source-time bootstrap still
precedes update ownership; this does not promise no effects from an old/missing
transport prerequisite before the runner is reached.

`app_maintenance_contents` emits the component-owned acquisition function closure
with checked `declare -f`. It emits definitions only, without current owner state,
descriptors, initialization or traps. Offline consumers do not select or name its
private dependencies. The cron updater's manager uses this public emitter when
publishing its self-contained worker. Both scheduled and manual execution acquire
the literal `cron-update-lxcs` key before config parsing or PVE effects, keeping the
FD through metadata, upgrades and graceful restoration. A busy worker returns 75;
unsafe or unavailable locking returns 69 before target effects. Refresh existing
workers and drain unguarded generations before relying on this serialization.

Addon update bundles pass their literal `addon_baseline` preparation to internal
`_run_update_script`, so baseline runs under the same owner but before pending and
FORCE admission. Its failure preserves the original status and prior flag without
arming app cleanup; invalid user options refuse before preparation. Core does not
know its addon consumer or expose arbitrary preparation as a user option.

A flag in
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

Software upgrades do not resize container resources. Core owns the returning
`confirm_container_resources(requiredCPU, requiredMiB, actualCPU, actualMiB, label)`
admission boundary. Literal decimal values are checked before comparisons.
Unknown requirements and insufficient CPU or RAM require explicit y/yes consent;
No, empty input and EOF refuse. An unknown actual allocation is a checked error.
The no-argument `check_container_resources` adapter measures nproc/free inside the
container, uses explicit baked LXC_REQUIRED_CPU/RAM fields when present, otherwise
the direct caller's existing var_cpu/var_ram values, and explicitly exits
on refusal or query failure, including under conditional callers. No unattended
or initial-confirm flag authorizes this consent. Frozen update bundles retain
their existing generation and caller defaults; this adds no framework refresh.

The LXC entry captures app-supplied var_cpu/var_ram locally before defaults and
menus. The pair is the script's resolved input at that point, not the eventual
allocation. It passes the pair explicitly into build's internal `_lxc_setup`.
The compatible `lxc_setup` wrapper supplies its caller's current declarations.
Both source-update modes converge after profile loading and bind local
LXC_REQUIRED_CPU/RAM fields from that pair before the public runner, so imported
fields and profile mutations cannot replace source-owned requirements. Initial
and repair preparation pass the same captured pair explicitly with the source ID.
New update bundles always declare both LXC_REQUIRED_CPU and LXC_REQUIRED_RAM,
empty when unknown, so ambient fields cannot supply missing provenance. Explicit
zero remains zero; absent or invalid requirements require consent, never a zero
fallback. The internal optional `--requirements <cpu> <ram> --` bundle prefix
follows the optional identity prefix; it is not an installer CLI option.

The PVE batch updater reads literal script requirements as data only. Modern
bundles keep their maintenance namespace separate from source identity: exactly
one canonical `declare -- LXC_SCRIPT_ID=<slug>` selects that source script.
Missing, duplicate or malformed identity means unknown requirements and explicit
consent, with no guessed NSAPP filename request. Strict whole-file legacy thin
wrappers retain their literal selected `/ct/<slug>.sh` target. Neither pulled
updaters nor fetched requirement scripts are evaluated. The batch measures the
selected CT using `pct exec <CT> -- nproc` and
`pct exec <CT> -- free -m`, then calls the same core owner before software effects.
Missing or malformed metadata is unknown, never a sizing instruction or a
satisfied check. On pre-update refusal/error it gracefully shuts down only a CT
successfully started by that batch, checks the resulting status and reports
restoration failures. Pre-existing running state and backups remain intact.
When targets remain, a separate explicit y/yes answer continues the batch; empty
input or EOF stops it. Partial summaries distinguish declined, failed admission,
failed updates, unattempted and temporary/busy targets.

Raw updater status 75 remains conservatively temporary/busy, not authenticated
lock refusal: a hook can also return 75. It skips automatic shutdown, backup
rollback and reboot eligibility, retaining any backup and a batch-owned start.
It never enters pre-update refusal cleanup. Final status prioritizes observed
updater 75, then the first admission refusal/error, then the ordinary result.
Successful-CT reboot handling and ordinary non-75 backup recovery remain separate;
a restored failed update is not reported as an all-updated success.
The backup producer brackets its checked vzdump with selected-storage JSON content
inventory through pvesh. Exactly one new typed CT backup, associated with the
selected storage/CT and a unique token in the script-owned notes line, produces
the per-CT receipt. A missing note is failure even if vzdump only warned and
returned0. Duplicate, reused, ambiguous or foreign artifacts fail before software
effects; old backups removed by configured retention are not new artifacts.
Recovery revalidates that exact receipt before any stop and passes its literal
storage volid, including PBS IDs, to pct restore. Destination rootfs storage stays
separate. No latest/local glob, hook override or retention override is used.
The JSON parser accepts only explicit inventory/select-new/verify-exact modes
with checked arity; expected volume IDs are data and never select parser behavior.
Backup recovery has one checked script-owned state/stop/config-storage/restore/start
sequence. Stop is skipped only for a positively observed stopped CT; an actual
stop must be followed by stopped-state readback. Each producer retains its native
failure status; start is reached only after restore succeeds. Failed recovery
stops the batch immediately and identifies the failed step/status without guessing
resulting state. Owned-start cleanup runs synchronously after the selected outcome,
never as a background shutdown competing with restore. It also verifies state
before skipping or completing shutdown. Reboot eligibility is collected only
after the completed outcome and owned-start cleanup, on a positively running CT
with the existing marker. An initially stopped CT stays stopped; it is never
started merely for reboot. Requested reboots revalidate running state immediately
before the command. Marker existence uses a guest POSIX-sh payload emitting the
exact token present or absent with status0, separate from pct-exec transport status.
Every nonzero transport status fails; empty/malformed/multiple output, trailing
newlines and NUL bytes fail closed. Output is compared as data, never evaluated.
A target stopped since collection is skipped; failed/unknown
queries and reboot-command failures report their status and set ordinary failure.
The final summary follows those outcomes, and the updater-75/first-admission/
ordinary-failure priority is retained.
One script-owned terminal selector applies that priority to every exit after batch
work begins, including fatal backup, restoration and unrecoverable update failures.
Those failures still abort at their original point; they do not advance to later
targets, automatic cleanup or reboot handling just to select the terminal result.

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

New update bundles also bake `LXC_SCRIPT_ID`, supplied explicitly from the literal
source footer through `build_container` and both initial/repair
`_prepare_container_bundles` calls. The bundle-owned validator accepts 1-64 ASCII
lowercase alphanumeric/dot/underscore/hyphen bytes, starting alphanumeric, without
a `.sh` suffix; malformed explicit tuples return 65 before productive work.
The ID is independent of APP/NSAPP and ambient/default `LXC_SCRIPT_ID` or
`var_lxc_*` values. It never renames maintenance, pending or backup ownership.
Old positional producers omit the field and remain unknown. This is declared
provenance, not authentication of arbitrary root-written code. Frozen bundles
are not automatically refreshed.

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

The separate manual PVE hardware tool uses `tools/pve/gpu-nvidia.func` for its
NVIDIA branch. Checked driver/CUDA-capability reads, proc records, dialog membership
and character-device metadata precede config effects. Its existing 500/11 warning
thresholds require explicit consent for known older versions; unknown data fails.
CUDA capability does not establish an installed toolkit. The selected device minor
is independent of menu position, and sparse numbered nodes are eligible.

All three manual GPU providers use `tools/pve/gpu-config.func`, one vendor-neutral
configuration owner. Its checked `gpu_config_contents` emitter owns the writer
and character-metadata closure. Providers retain their public APIs; NVIDIA's
`nvidia_write_lxc_config` is a compatibility adapter, not another writer. The
caller separately checked-loads the common owner before selected GPU effects;
missing/partial support fails that GPU while USB remains independent.
The shared owner publishes active `lxc` pairs through native PVE config
lock/load/check/write APIs. Strict parsing, loss audits and native serializer
roundtrips must preserve unrelated active fields, foreign pair order, pending and
snapshots before publication. Duplicate singleton/section input, discarded active
snapstate, normalization loss (including referenced `unusedX`) and conflicting
mount destinations refuse specifically. Mount targets are rootfs-relative
`dev/*`; equivalent existing entries are reused. Checked CFS refresh and
raw/cached digest/semantic readback remain inside the lock. Write/readback failure
reports uncertainty without rollback. Failed/declined GPU targets, including
mixed-feature partial changes, never enter automatic reboot eligibility.
Requested reboots require a checked, positively running `pct status`; stopped CTs
stay stopped and apply configuration on their next start. Unknown/failed queries
and reboot failures remain errors without Restarted success. No/EOF requests no
lifecycle effect. The manual utility needs no scratch allocation or local EXIT
owner; the loaded framework retains its existing spinner cleanup.
This config outcome does not prove GPU operation, toolkit availability or per-card
security isolation; existing major-wide/DRM compatibility policy is retained.

The same shared GPU owner checks the configured unified device program rather
than the presence of an allow string. Its helper-local source-characterized
LXC 5/6/7 model resolves the PVE OS/common prelude, generated device/console rules
and ordered active suffix, including include and controller-clear behavior.
Global rules reset the surviving program; exact native access strings retain
replacement identity, and every nonempty r/w/m request mask is checked for actual
required character tuples. Missing allowlist rights may add the existing
major-wide rule when the native list is nonempty. An entirely empty native list
attaches no additional device program: mounts may be added, but no device grant
is appended. Ineffectual entries still activate the default program. This follows
LXC 5/6/7 `cgfsng.c:cgfsng_devices_activate` (7.0.0 lines 2972-2976), rather than
assuming the list's allowlist/denylist type alone establishes its default.
Already-permitted denylist devices need no ineffective
allow; foreign denial effects, including other minors affected by a broad grant,
cannot be neutralized. Foreign entries and global mode are never rewritten.
Native controller-list clears are resolved before preparing surviving device
values; a device-program reset cannot excuse an invalid surviving rule. Numeric
device fields retain native base-zero parsing, including leading-zero octal.
Typed structured `devN` deny-write constraints also forbid newly granted write
for that mapped tuple, including another minor sharing a broad grant's major.
Already-configured write is not a new relaxation. No global mode or grant shape
is changed to bypass a refusal.
Directory comparison distinguishes empty/nonempty activation only in allowlist
mode. Empty denylist and denylist with only ineffectual allows both permit all
devices at this layer, so their directory order does not cause a false refusal.

Policy dependencies are read-only, bounded regular files/directories or device
metadata, never special-file contents. Identity, bytes and membership are captured
and revalidated before publication and readback. Directory load order is not
assumed lexical: commuting transforms or bounded complete order exploration must
prove consistent policy; otherwise the exact dependency is refused. Missing
required files, cycles, unsupported/changing data and uncharacterized
loader-relative dependencies fail before publication. Native optional absent
directories remain captured, revalidated dependencies. External files are not
locked by the CT owner, so this is
configured consistency at validation time, not ancestor-BPF, DAC or future-start
permission proof. Native config/serializer/readback fidelity remains unchanged.
Included file lexing follows `parse.c:lxc_file_for_each_line_mmap` and
`confile.c:parse_line` with `string_utils.c:lxc_char_left_gc/right_gc`: CR/LF
parts, first-NUL termination and space/tab trimming. The native `devices` prefix
is classified without a suffix boundary; unsupported surviving controllers refuse
specifically. Control bytes in rendered active LXC pairs refuse before publication
instead of bypassing the device projection.

Native PVE startup applies pending deletions and whole-value replacements before
generating LXC config. Under the same lock, the owner compares the candidate's
consumed logical lxc/devN/ostype/unprivileged/console inputs with that pending
result. A material change refuses with the exact key; unrelated pending, proven
no-ops/defaults and snapshots remain unchanged. Comparison uses the candidate:
adding lxc can make a previously vacuous pending deletion effective. The owner
never invokes side-effecting apply-pending or edits the pending section.

Optional NVIDIA helper transport/source failure is isolated from other features.
The component-owned checked `nvidia_helper_contents` emitter supplies its complete
runtime function/dependency closure, including `msg`, rather than caller prefix
discovery. It emits definitions only, without imported state, descriptors,
initialization or traps. A strict child must finish both sourcing and emission
before import; missing emitter, emission failure/early exit or empty output leaves
NVIDIA unavailable. Older helpers without this emitter do not satisfy the ABI:
selected NVIDIA reports the unavailable helper while unrelated features continue.
Stale required public functions are removed before loading; partial output cannot
borrow them. NVIDIA availability is guarded and its required API is checked when
selected. Intel/AMD passthrough success is
recorded before the returned tool-stage result, so a tool failure retains known
partial changes and excludes that CT from automatic restart.
Intel/AMD now submit active config requests to the common owner with checked
actual character tuples. AMD does not infer KFD major238; Intel keeps its exact
framebuffer-minor and DRM major-wide shape. Their actual providers explicitly
return config, transport and required child package failures even under conditional
callers. A typed OS-probe value is separate from pct status: transport/grep errors
are not non-Alpine. Intel's intentionally optional group failures warn; AMD's
required group failures return nonzero. Package names remain unchanged.
Intel repository enablement uses native APT source identities and verified archive
metadata, not a legacy-file assumption or a fixed-release repository template.
Only missing supported components are appended to active configured Debian/Ubuntu
entries; URIs, suites, source options, disabled entries and operator fragments are
preserved. Native APT validates the complete projection before publication, and
source aliases are resolved with captured link/directory identities. A Linux
metadata-only inode pin precedes regular-file byte reads; special targets are
never opened for I/O. Sufficient sources may be symlinked or hardlinked. Needed
edits preserve the alias and resolved target ownership/mode/xattrs; hardlinked
write targets and multiply named source targets refuse with the exact path.
Per-source publication prepares the candidate at a private mode0700 same-filesystem
`.gpu-intel-recovery.XXXXXXXX/source`, then uses Linux renameat2 RENAME_EXCHANGE:
the live path is never removed, and that recovery pathname atomically receives the
actual displaced inode. An exact recovery intent is emitted before exchange; the
operand/directory are never registered for automatic cleanup, including publisher
death or normal exit before readback. The native ABI is checked, and a private
same-filesystem exchange probe must succeed before live publication. Unsupported
architecture/kernel/filesystem refuses without a two-step fallback. Conflicts
fail with possible partial-change and exact recovery-path diagnostics, without
automatic exchange-back/restore over another writer. The original inode retains
operator ownership/metadata even after success and is not automatically removed:
an uncooperative editor may still hold it open.
This bounded recovery custody does not promise a lock against other writers or
an all-source transaction. Both index refreshes require Error-Mode=any before
package installation, so a transient second refresh cannot admit stale indexes.
Sufficient configured repository versions are a no-op; an installed-only package
does not count as configured source support. Unknown/custom archives are
not replaced with foreign repositories; real read/parse/update/package failures
remain failures. Debian requires non-free for the media package; Ubuntu uses
universe/multiverse. Repository component enablement does not manufacture an
unavailable package: the unchanged intel-opencl-icd requirement has no candidate
in current trixie metadata and must retain its genuine APT failure there.

`header_info` is not a lifecycle hook — it's a display hook invoked by
`render_header()` early in the bootstrap (after `color` / `vm_init_colors`,
before `catch_errors`). If the script defines `header_info()`, the
framework's `render_header()` dispatches to it; otherwise a generic
fallback (`header_info_fallback()`) displays the app name.

Screen clearing belongs to core's `terminal_clear()`. It returns 0 without output
when stdout is not a TTY or TERM is unset, empty or `dumb`. For a usable stdout
terminal it invokes the external `clear` command, treating missing executables,
unsupported terminfo and other cosmetic failures as nonfatal and suppressing only
that command's stderr. It does not set TERM, alter options/traps or mask productive
command failures. Custom headers and menus use this same boundary after core is
loaded. PVE scripts load their existing bootstrap before their first header;
the cron manager declares its custom banner first and renders it after bootstrap.

BookOrbit's cold updater discovers installed configuration and database library
roots before runtime/service/source effects, then rechecks after service stop.
Its app-owned restricted environment grammar refuses unsupported service overrides;
the system PostgreSQL client performs read-only discovery independently of app
dependencies. Existing literal keep paths protect config and in-tree persistence
through checked replacement; generated source/build overlaps refuse. Updates do
not rotate keys, alter operator units/ports or change PostgreSQL major versions.
Fresh and update paths build only frozen client/server dependency closures while
retaining upstream prebuild hooks. Modeled preservation assertions and the separate
native BookOrbit consumer have different proof scopes, documented in tests/README.md.
BookOrbit keeps the literal service entry root distinct from its physical directory.
Discovery captures physical path/device/inode and lexical entry identity before
configuration/query work. One app-owned closure walks config, caller and typed DB
paths component by component, preserving material prefix links and referents, not
ordinary traversal parents. Linux metadata-only O_PATH/NOFOLLOW descriptors bind
each reached mount ID and inode to mountinfo coordinates. App-root and descendant
mount charts project external bind aliases back into relative keeps; hidden,
unreachable, code-overlapping or uncharacterized projections refuse. No recursive
data crawl, mover, shared path registry or provider policy is introduced.

A read-only repeatable-read SQL session inventories the migration ledger, catalog
and 12 source-pinned path fields plus derived dock thumbnails. Unknown ledger/schema
combinations refuse rather than guessing empty data. Config uses physical service
cwd semantics; literal DB dot-dot paths refuse. Typed optional and source-proven
reader seeds admit witnessed absence independently of creation permission.
Nonmaterial missing tails still undergo code/ancestor/mount projection admission;
existing prefix links remain material, but absent subtrees are not owned.
The finite contract is pinned to v2.0.1 and v3.7.0.
Versioned NUL-delimited metadata precedes, but never becomes, a replacement keep.
It binds config bytes, service view, typed SQL inputs, dependency identities and
relevant topology within each pass and across service stop, even for unchanged
keep sets. A remap refuses before replacement and retains pending/stopped state.
The cross-pass service view uses a typed ExecStart configuration projection:
executable, argv and ignore-errors remain inputs, while validated execution
timestamps, PID and exit bookkeeping do not. The finite systemd257 text record
must parse completely; unsupported records refuse. Raw service snapshots and live
PID/birth still bind each individual discovery pass. Public metadata includes the
typed command and service-view hash, not inline environment or config values.
Bounds are 64MiB SQL output, 250000 distinct seeds, 512000 records, 1000000 prefix
observations, 60 seconds, 4096 path bytes/components and 40 symlink expansions;
exhaustion refuses65 without a partial plan. This is validation-time consistency,
not an atomic lock against nonparticipating administrators. Operator units and
data remain in place; unsupported service filesystem views refuse without repair.

One app-owned config-input owner admits metadata before any config byte I/O and
resnapshots through that same boundary. Primary .env retains its single-link
nonsymlink leaf contract; optional server/.env permits regular aliases/hardlinks.
Every optional lookup enters the common closure, preserving existing prefix links
and recording absence without inventing a file/subtree keep. Only an admitted
ordinary regular O_PATH descriptor is reopened through
this process's trusted /proc/self/fd, fstat-matched and read to at most1MiB+1;
overflow refuses before parsing. All FDs close in finally. Presence, alias/target
identity and byte hashes are compared within-pass and across quiescence, including
unchanged bytes on a replacement inode. Raw config values never enter diagnostics
or public metadata; UTF8/environment grammar and precedence remain unchanged.

Ordinary data filesystems are not rejected by name. Coordinate admission rejects
API/magic filesystems and unprovable representations instead. Btrfs subvolume
stat devices remain distinct from the mountinfo superblock device. NFS deliberately
reports `/` as every mount root, so its decoded export-source path supplies the
coordinate base. All projections still require reached mount and fstat identity;
cross-superblock application/network aliases refuse as unprovable. This is a
kernel VFS contract, not native qualification of every storage backend.
Source-proven missing DB reader dependencies retain prefix/link/mount/absence
witnesses without creating data; absence is separate from creation permission.
Typed tool/resource inputs use the same closure. Commands enumerate the accepted
service PATH (primary EnvironmentFile over inline, otherwise installed systemd's
default with manager ambiguity admission), never optional dotenv or updater PATH.
Nest fallback fills only unset application variables. Commands retain a
conservative union of candidates without claiming first-executable resolution.
Optional missing tools remain optional. KOReader overrides are directories;
generated-code and uncharacterized in-app executable targets remain refusals.

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

Template-cache coordination is persistent metadata, independent of those temporary
roots. `_template_prepare_archive` resolves the selected storage/name afresh and
uses checked native `pvesm list --content vztmpl` storage activation to prepare
the configured cache parent. It never creates a guessed directory on an inactive
storage mount. `_template_lock_acquire` keys one empty lock inode by that parent's
device/inode and the archive basename (SHA256 for a bounded filename), under
`/var/lib/scripts-underground/template-locks`. Symlink/bind aliases of one cache
therefore serialize together; different cache directories or names remain independent.
The directory must be root-owned, private0700 on disk, with root-owned ancestors
that are not group/world-writable;
existing incompatible paths are refused, never chmodded. Lock paths
must be nonsymlink regular root-owned0600 files with one link and zero bytes. The
append-open descriptor and path identities are checked before real flock waits.

Initial classification, removal, downloads, final archive/list validation and the
openEuler patch all belong to this owner. Repair and local fallback resolve and
re-acquire their target, then recheck after waiting; a competing creator's valid
publication is reused. Selection/operator prompts and LXC-stack upgrades happen
outside the hold. Every `pct create` runs after release and uses its own PVE lock.
The existing ten30-second waits remain bounded; timeout diagnostics show kernel
holders instead of advising inode deletion. Lock files are never unlinked for
mtime, waiter timeout, ERR, EXIT or process failure. Generic EXIT does not own a
caller variable named `lockfile`; resource owners retain their own cleanup.

Template names must match `^[a-zA-Z0-9][a-zA-Z0-9._+-]*$`; invalid names or an
unavailable resolved cache parent fail220. Archive symlinks and nonregular or
unreadable archives are refused with221, without following or replacing their
targets. Refusals identify the offending path and condition. The prepare owner
classifies failures at its safety/archive boundary through a checked caller output,
independently of native status numbers. Resolve/storage-preparation/namespace/lock
failures remain fatal. A non-local repair producer or archive-validation failure
skips pct reuse of those known-invalid bytes and enters the existing checked local
fallback; local repair and failed fallback retain their exact terminal status.
A producer returning200 therefore does not masquerade as a lock refusal, and a
real lock refusal cannot be swallowed into fallback. Initial download exhaustion
remains222 and failed final storage-list validation223.

The cache owner stops an existing spinner before opening its descriptor and uses
non-spawning progress messages during the hold. Synchronous archive producers and
validators deliberately inherit the FD: if the launcher dies, a surviving producer
keeps protection until its work ends. Normal release closes the owner's FD after
those children complete; kernel closure handles failure/death. A background UI
process must never inherit this descriptor. This protocol is host-local and does
not coordinate with other PVE nodes or already-running old-version creators.
Drain those old creators before deploying the new namespace; no legacy temporary
lock cleanup or compatibility acquisition is attempted.
Keys identify the active local mount instance: a remount may create new metadata,
and separately mounted exports with different device identities do not share keys.

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

GitHub, Codeberg and GitLab binary `.deb` deployment share the internal APT
installation boundary. `FORCE_DEPLOY=1` requests `--reinstall`, so an installed
same-version package is unpacked/configured again instead of a successful APT
no-op. Unforced installation is unchanged. Each adapter retains its selected
package, conffile options, `$STD` handling, dpkg fallback and failure status;
failed required package work does not publish its release marker. The URL `.deb`
route also supports this opt-in force behavior, without a version marker or any
change to unforced URL installs. This contract does not change repository
dependency installation or other package backends.

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
