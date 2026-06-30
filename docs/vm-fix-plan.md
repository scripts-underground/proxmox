# Plan: VM Fix — Align Code with Migration Doc Spec

## Goal

Bring framework and VM scripts in line with the VM migration doc
(`docs/migration.md`) and the hook architecture (`docs/architecture.md`).

## Commit breakdown

### Commit A — `feat(framework): add render_header dispatching to header_info hook`

**Goal:** Framework provides `render_header()` that dispatches to the script's
custom `header_info()` or a generic fallback. `header_info` is now a first-class
hook (AST already updated, `4fba16c`).

**Files: `misc/core.func`, `misc/bootstrap/lxc`, `misc/bootstrap/vm`**

#### Step 1 — Add `render_header()` and `header_info_fallback()` to `core.func`

Insert before the existing `header_info()` block (around line 815, just
before the doc-comment and the `header_info()` function definition):

```bash
# ------------------------------------------------------------------------------
# header_info_fallback()
#
# - Generic header fallback when no header_info hook is defined by the script
# - Clears screen and displays the app name
# ------------------------------------------------------------------------------
header_info_fallback() {
  clear
  echo -e "${BL}${BOLD}${APP:-}${CL}\n"
}

# ------------------------------------------------------------------------------
# render_header()
#
# - Dispatches to script-defined header_info() hook if present
# - Otherwise calls header_info_fallback() for a generic display
# - Called early in the bootstrap (after color, before catch_errors)
# ------------------------------------------------------------------------------
render_header() {
  if declare -F header_info >/dev/null 2>&1; then
    header_info
  else
    header_info_fallback
  fi
}
```

Insert this block BEFORE the current `# header_info()` doc-comment and
`header_info() {` function definition.

#### Step 1b — Delete framework's `header_info()` from `core.func`

The framework's own `header_info()` function collides with the script's
custom `header_info()` hook. After `build.func` sources `core.func`, the
framework's version overwrites the script's. `render_header()` then always
finds the framework version and never dispatches to the script's ASCII art.

Delete the entire block: the `# header_info()` doc-comment PLUS the
`header_info() { ... }` function body (8-10 lines).

#### Step 1c — Update framework call sites in `build.func`

All 8 places that call `header_info` for internal menu screens must now
call `header_info_fallback`:

| Line | Change |
|---|---|
| 578 (comment) | `# - Called from setup_script() after header_info()` → `header_info_fallback()` |
| 1789 | `header_info` → `header_info_fallback` |
| 2557 | `header_info` → `header_info_fallback` |
| 3355 | `header_info` → `header_info_fallback` |
| 3405 | `header_info` → `header_info_fallback` |
| 3414 | `header_info` → `header_info_fallback` |
| 3432 | `header_info` → `header_info_fallback` |
| 3447 | `header_info` → `header_info_fallback` |
| 3451 | `header_info` → `header_info_fallback` |

After this, framework menu screens use the simpler generic fallback
(`header_info_fallback`) and `render_header()` correctly dispatches:
scripts that define `header_info()` get their ASCII art; scripts that
don't get `header_info_fallback()`. No collision.

#### Step 2 — Add `render_header` call to `bootstrap/lxc`

Current:
```
variables
color
catch_errors

start
```

Replace with:
```
variables
color
render_header
catch_errors

start
```

#### Step 3 — Add `render_header` call to `bootstrap/vm`

Current:
```
vm_validate
vm_init_colors

declare -F post_install_script >/dev/null 2>&1 && post_install_script
```

Replace with:
```
vm_validate
vm_init_colors
render_header

declare -F post_install_script >/dev/null 2>&1 && post_install_script
```

**Validation for Commit A:**
- `bash -n misc/core.func misc/bootstrap/lxc misc/bootstrap/vm`
- Framework files parse clean

---

### Commit B — `feat(vm): complete VM lifecycle with VM_ variable contract`

**Goal:** `vm.func` reads all variables with `VM_` prefix (preventing LXC
namespace leaks). `vm_setup()` fires `pre_build_script` hook. `vm_start()`
conditionally starts only if `VM_START=yes`. `bootstrap/vm` calls the full
lifecycle.

**Files: `misc/vm.func`, `misc/bootstrap/vm`**

#### Step 1 — Rename unprefixed variables in `vm.func`

Replace each occurrence with the `VM_`-prefixed name.

| Old name | New name | Lines |
|---|---|---|
| `CORE_COUNT` | `VM_CORE_COUNT` | 64 |
| `RAM_SIZE` | `VM_RAM_SIZE` | 64 |
| `HN` | `VM_HN` | 65 |
| `BRG` | `VM_BRG` | 65 |
| `MAC` | `VM_MAC` | 65 |
| `DISK_SIZE` | `VM_DISK_SIZE` | 83, 88 |
| `VMID` | `VM_VMID` | 62, 63, 68, 73, 75, 76, 81, 88, 89, 94, 95, 96 |
| `STORAGE` | `VM_STORAGE` | 68, 73, 75, 76 |

For `VMID` and `STORAGE`: do line-by-line edits. Here are the exact
replacements (applied after renames of other variables):

- Line 62: `"$VMID"` → `"$VM_VMID"`
- Line 63: `"$VMID"` → `"$VM_VMID"`
- Line 65: `"$VMID"` → `"$VM_VMID"` (contextual check — the `$VMID` at
  63 is inside `qm create "$VMID"`)
- Line 68: `pvesm alloc "$STORAGE" "$VMID" "vm-${VMID}-disk-0"` →
  `pvesm alloc "$VM_STORAGE" "$VM_VMID" "vm-${VM_VMID}-disk-0"`
- Line 73: `qm importdisk "$VMID" "$VM_FILE" "$STORAGE"` →
  `qm importdisk "$VM_VMID" "$VM_FILE" "$VM_STORAGE"`
- Line 75: `"${STORAGE}:vm-${VMID}-disk-0"` →
  `"${VM_STORAGE}:vm-${VM_VMID}-disk-0"`
- Line 76: `"${STORAGE}:vm-${VMID}-disk-1"` →
  `"${VM_STORAGE}:vm-${VM_VMID}-disk-1"`
- Line 81: `"$VMID"` → `"$VM_VMID"`
- Line 88: `"$VMID"` → `"$VM_VMID"`
- Line 89: `"$VMID"` → `"$VM_VMID"`
- Line 94: `"$VMID"` → `"$VM_VMID"`
- Line 95: `"$VMID"` → `"$VM_VMID"`
- Line 96: `"$VMID"` → `"$VM_VMID"`

Note: `VMID` at line 65 is in the `-name "${HN:-vm}" ...` string — check
carefully whether it appears bare or as part of a larger expression. The
`grep` result `-name "${HN:-vm}" -net0 ... macaddr=${MAC:-$GEN_MAC}"` does
NOT contain `$VMID` at line 65 — only at lines 62, 63, 68, 73, 75, 76, 81,
88, 89, 94, 95, 96. So this needs no change at line 65.

#### Step 2 — Add `VM_START` conditional to `vm_start()`

Current `vm_start()` (lines 92-97):
```bash
vm_start() {
  VM_PASSWORD="${VM_PASSWORD:-$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c13)}"
  qm set "$VMID" --ciuser root --cipassword "$VM_PASSWORD" >/dev/null 2>&1 || true
  qm start "$VMID" >/dev/null
  msg_ok "Started VM $VMID"
}
```

Replace with (after VMID→VM_VMID renames applied):
```bash
vm_start() {
  if [[ "${VM_START:-yes}" != "yes" ]]; then
    msg_info "Skipping VM start (VM_START=$VM_START)"
    return 0
  fi
  VM_PASSWORD="${VM_PASSWORD:-$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c13)}"
  qm set "$VM_VMID" --ciuser root --cipassword "$VM_PASSWORD" >/dev/null 2>&1 || true
  qm start "$VM_VMID" >/dev/null
  msg_ok "Started VM $VM_VMID"
}
```

#### Step 3 — Add `vm_setup()` to `vm.func`

Insert AFTER `vm_start()` (after line 97 block, before `vm_wait_for_ssh()`):

```bash
# ------------------------------------------------------------------------------
# vm_setup()
#
# - Pre-build preparation: fires pre_build_script hook (if defined)
# - Script's start_script passes through to default_settings/advanced_settings
# ------------------------------------------------------------------------------
vm_setup() {
  declare -F pre_build_script >/dev/null 2>&1 && pre_build_script
}
```

#### Step 4 — Complete `bootstrap/vm` with full lifecycle

Current:
```
source <(curl ... build.func)
source <(curl ... vm.func)

vm_validate
vm_init_colors

declare -F post_install_script >/dev/null 2>&1 && post_install_script
```

Replace with:
```
source <(curl -fsSL "${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}/misc/build.func") 2>/dev/null
source <(curl -fsSL "${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}/misc/vm.func") 2>/dev/null

if ! declare -F install_script >/dev/null 2>&1; then
  echo "Error: install_script() not defined"
  exit 1
fi

vm_validate
vm_init_colors
render_header
catch_errors

vm_setup
vm_create
vm_start
complete_install
```

Note: `catch_errors` is provided by `error_handler.func` which is sourced
by `build.func` at the top of the bootstrap.

**Validation for Commit B:**
- `bash -n misc/vm.func misc/bootstrap/vm`
- `grep -n 'CORE_COUNT\|RAM_SIZE\b\|HN\b\|BRG\b\|MAC\b\|DISK_SIZE\b\|VMID\|STORAGE' misc/vm.func` — no unprefixed matches outside internal locals (genmac, local variables, VM_PASSWORD)
- Each `VM_` name present in the file

---

### Commit C — `refactor: rename start() to lxc_setup()`

**Goal:** LXC lifecycle function named for what it does, matching the
`vm_setup` naming convention.

**Files: `misc/build.func`, `misc/bootstrap/lxc`**

#### Step 1 — Rename function definition in `build.func`

Line 3818: `# start()` → `# lxc_setup()`
Line 3825: `start() {` → `lxc_setup() {`

#### Step 2 — Rename call sites in `build.func`

Find all standalone `start` calls (not `systemctl start`, `START_VM`, etc.):
```bash
grep -n '\bstart\b' misc/build.func | grep -v "systemctl\|#\|START_VM\|START\b"
```

Replace any bare `start` function calls with `lxc_setup`. The primary call
site is in `misc/bootstrap/lxc` line 13.

Check also if any other framework files reference the `start()` function
by name (e.g., `declare -F start` or `if declare -F start...`).

#### Step 3 — Update `bootstrap/lxc`

Line 13: `start` → `lxc_setup`

**Validation for Commit C:**
- `bash -n misc/build.func misc/bootstrap/lxc`
- `grep -n 'lxc_setup' misc/build.func misc/bootstrap/lxc` — function defined and called

---

### Commit D — `fix(scripts): rename VM variables to VM_ prefix per migration doc`

**Goal:** All 11 VM scripts (`scripts/vm/*.sh`) rename their globals from
upstream names to `VM_`-prefixed names, matching the contract in `vm.func`.

**Files:** All files under `scripts/vm/`

#### Step 1 — For each VM script, apply variable renames

Open each script and apply these replacements in both `default_settings()`
and `advanced_settings()`:

| Find | Replace with | Notes |
|---|---|---|
| `VMID=` | `VM_VMID=` |  |
| `MACHINE=` | `VM_MACHINE=` |  |
| `CPU_TYPE=` | `VM_CPU=` |  |
| `FORMAT=` | `VM_DISK_FORMAT=` |  |
| `START_VM=` | `VM_START=` |  |
| `CORE_COUNT=` | `VM_CORE_COUNT=` |  |
| `RAM_SIZE=` | `VM_RAM_SIZE=` |  |
| `DISK_SIZE=` | `VM_DISK_SIZE=` |  |
| `DISK_CACHE=` | `VM_DISK_CACHE=` |  |
| `HN=` | `VM_HN=` |  |
| `BRG=` | `VM_BRG=` |  |
| `MAC=` | `VM_MAC=` | But not `VM_MAC=` double-prefix; use grep to confirm uniqueness |
| `VLAN=` | `VM_VLAN=` |  |
| `MTU=` | `VM_MTU=` |  |
| `METHOD=.*` | (remove entire line) | Telemetry remnant |
| `GEN_MAC=02:\$.*` | (remove entire line) | Defined in vm.func now |
| `RANDOM_UUID="\$\|RANDOM_UUID=\"\` | (remove entire line) | Telemetry remnant |
| `$VMID` | `$VM_VMID` | (if used in any remaining inline code) |
| `${VMID}` | `${VM_VMID}` |  |
| `$MACHINE` | `$VM_MACHINE` | (if used) |
| `$CPU_TYPE` | `$VM_CPU` |  |
| `$START_VM` | `$VM_START` |  |
| `$CORE_COUNT` | `$VM_CORE_COUNT` |  |
| `$RAM_SIZE` | `$VM_RAM_SIZE` |  |
| `$DISK_SIZE` | `$VM_DISK_SIZE` |  |
| `$HN` | `$VM_HN` |  |
| `$BRG` | `$VM_BRG` |  |
| `$MAC` | `$VM_MAC` |  |
| `$VLAN` | `$VM_VLAN` |  |
| `$MTU` | `$VM_MTU` |  |
| `$DISK_CACHE` | `$VM_DISK_CACHE` |  |

#### Step 2 — Verify per-script

For each script after replacements:
```bash
bash -n scripts/vm/<name>.sh
grep -n "MACHINE\|CPU_TYPE\|FORMAT\|START_VM\|CORE_COUNT\|RAM_SIZE\|DISK_SIZE\|DISK_CACHE\|HN\|BRG\|MAC\b\|VLAN\b\|MTU\b" scripts/vm/<name>.sh | grep -v "VM_\|#\|MAC1\|VLAN1\|MTU1"
```
Should return zero matches (except `MAC1`, `VLAN1`, `MTU1` which are whiptail
temporary variables, not the globals).

**Validation for Commit D:**
- All 11 VM scripts pass `bash -n`
- Grep sweep confirms no unprefixed globals remain

---

## Execution order

1. **A** (render_header — independent)
2. **B** (VM lifecycle — depends on A, bootstrap/vm touched by both)
3. **C** (lxc_setup — depends on A, bootstrap/lxc touched by both)
4. **D** (VM scripts — depends on B, vm.func must read VM_ vars first)

## Final validation

```bash
# All framework files parse
for f in misc/*.func; do bash -n "$f" && echo "OK: $f"; done

# Bootstrap shims parse
bash -n misc/bootstrap/lxc
bash -n misc/bootstrap/vm

# No unprefixed VM globals remain in vm.func
grep -n 'CORE_COUNT\|RAM_SIZE\b\|HN\b\|BRG\b\|MAC\b\|DISK_SIZE\b\|VMID\|STORAGE' misc/vm.func

# All 11 VM scripts pass shellcheck
for f in scripts/vm/*.sh; do shellcheck --severity=warning "$f" && echo "OK: $f" || echo "FAIL: $f"; done

# AST regeneration
go run ./tools/ast/.

# Jekyll build
bundle exec jekyll build
```
