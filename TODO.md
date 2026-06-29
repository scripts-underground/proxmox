# TODO

## LXC Script Migration — Done
- [x] 87 total LXC scripts with matching metadata (11 existed, 76 migrated via automation + fixes)
- [x] Fixed affine.sh — heredoc truncation in update_script()
- [x] Fixed 10 OS templates — missing `}` in empty install_script()
- [x] Fixed godoxy.sh — added install_script() from install/deferred/
- [x] All follow bootstrap pattern: `install_script()` + `update_script()` + `post_install_script()`

## LXC Script Migration — Deferred (incomplete upstream, need install logic written)
- [ ] **web-check** — no install script exists upstream at all
- [ ] **arm** — has install/deferred/arm-install.sh + json/arm.json, needs migration
- [ ] **blinko** — has install/deferred/blinko-install.sh, needs migration
- [ ] **docspell** — broken (references `/opt/bookstack`), has deferred/docspell.json
- [ ] **jumpserver** — has install/deferred/jumpserver-install.sh, non-standard vars
- [ ] **maxun** — has install/deferred/maxun-install.sh + deferred/maxun.json
- [ ] **ocis** — has install/deferred/ocis-install.sh, needs migration
- [ ] **piler** — has install/deferred/piler-install.sh, needs migration
- [ ] **polaris** — has install/deferred/polaris-install.sh, empty update_script()
- [ ] **roundcubemail** — has install/deferred/roundcubemail-install.sh, uses anti-patterns
- [ ] **rybbit** — has install/deferred/rybbit-install.sh, needs migration
- [ ] **transmission-openvpn** — has install/deferred/transmission-openvpn-install.sh

## Pre-release — Framework fixes

### LXC framework — code deltas
- [ ] **`post_build_script` double-fire** — remove the invocation from `misc/bootstrap/lxc:15`. The `build.func`-internal call is the single canonical one. Verify with a script that defines `post_build_script` that it runs exactly once.
- [ ] **Rename `description()` → `complete_install()`** in `misc/build.func`. Update the call in `misc/bootstrap/lxc` from `description` to `complete_install`.
- [ ] **Move `post_install_script` invocation** from `misc/bootstrap/lxc` into `complete_install()` in `build.func`. Remove the shim's direct call.
- [x] **Move `msg_ok "Completed Successfully!"`** from `misc/bootstrap/lxc` into `complete_install()` after `post_install_script` returns.
- [x] **Verify no other files** call `description` directly (found: `bootstrap/lxc` and possibly `bootstrap/addon` or `bootstrap/vm`).
- [x] **Remove all telemetry** — deleted `misc/api.func`, stripped `post_*_to_api`, `DIAGNOSTICS`, `diagnostics_*` from all `.func` files and `bootstrap/pve`. Updated `docs/function-reference.md`.
- [x] **Follow-up sweep: DIAGNOSTICS dead-code cleanup** — removed orphan curl tail in error_handler.func (parse error), removed live `post_to_api` call in build.func, removed write-only `METHOD=` variables and orphan `RANDOM_UUID`/`EXECUTION_ID` exports, removed orphan `5)` case branch in settings_menu, fixed stale doc-comments and external docs.
- [ ] **Shadowed function: `cleanup_lxc`** — both `core.func` and `install.func` define it. `install.func` wins inside the container (sourced later). Confirm this is intentional (install.func version supports all OS families; core.func version is Alpine/Debian only). If intentional, document the shadowing.

### Architecture docs — stubs to fill
- [ ] **§3.2 Addon bootstrap** — `misc/bootstrap/addon` detailed walk-through.
- [ ] **§3.3 PVE bootstrap** — `misc/bootstrap/pve` detailed walk-through.
- [ ] **§3.4 VM bootstrap** — `misc/bootstrap/vm` detailed walk-through.
- [ ] **§4.2-§4.4 Install paths** for Addon, PVE, VM.
- [ ] **§5.2-§5.4 Variable propagation** for Addon, PVE, VM.
- [ ] **§6.2-§6.4 Extension points** for Addon, PVE, VM.

### Per-script audit
- [ ] **LXC scripts (87)** — verify each follows the spec: REPO_BASE at top, required function order, no inline helper redefinitions, no direct calls to `start`/`build_container`/`description`.
- [ ] **Addon scripts (6)** — verify each removes inline helper redefinitions (check copyparty, filebrowser, glances).
- [ ] **PVE scripts (10)** — verify REPO_BASE is set, bootstrap sourcing works (some scripts source bootstrap in the middle, some don't source at all).
- [ ] **VM scripts (11)** — verify they match whatever VM contract emerges after filling the stubs.

### AST rendering — follow-ups (not blocking release)
- [ ] **Rendering issues** — visual issues noted during browser validation of the source view token-driven renderer. Enumerate and fix per reported symptoms.
- [ ] **Array subscript tokenization** — `ARR[0]=foo` subscript `[0]` is currently emitted as plain bytes inside `var-assign`. Tier 4 arithmetic-token pass should cover `Assign.Index *ArithmExpr`. See `docs/ast-tokens-implementation.md`.
- [ ] **Tier 4 arithmetic tokens** — operators inside `$(( ))`, `(( ))`, `let X=1+1`. See `docs/ast-tokens-implementation.md`.
- [ ] **Function-call cross-linking** — `function-call` tokens as clickable links to `function-name` declarations.
- [ ] **Token-first rendering** — pivot AST schema so tokens (not `source` text) are the canonical script representation. See `docs/token-first-rendering.md`.

## Other Script Types (not yet started)
- [ ] **Addon scripts** — 6 remaining (copyparty, cronmaster, filebrowser, glances, jellystat, mqttx), ~9 more from upstream `tools/` + `addon/`
- [ ] **Host Addon scripts** (temp name) — 4 identified (add-iptag, add-tailscale-lxc, code-server, netdata), need host-level bootstrap, ~10 more from upstream. Not yet created.
- [ ] **PVE scripts** — 10 existing, ~20 more from upstream `tools/pve/`
- [ ] **VM scripts** — 11 existing, ~5 more from upstream `vm/`
- [ ] **Regenerate `scripts.json`** — auto-generated on `jekyll build`
