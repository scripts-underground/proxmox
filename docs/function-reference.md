# Function reference — LXC framework helpers

> Audience: maintainers extending the framework (`misc/*.func` files) and
> script authors writing `install_script()` bodies. Cross-referenced from
> `docs/architecture.md §6`.

Each section below corresponds to one framework file. Functions are grouped
by role. Each entry describes the contract: purpose, inputs, outputs, and
who calls it. Implementation details are in the source; this doc tells you
what a function needs and what it produces.

## `misc/core.func` — Common helpers

### Initialization & setup

- **`load_functions()`** — Runs color/formatting/icons/default_vars/set_std_mode in order. Called once at file source time. Guarded by `__FUNCTIONS_LOADED`.
- **`color()`** — Sets ANSI color globals (`YW`, `BL`, `RD`, `GN`, `CL` etc.). Called by bootstrap shim, `load_functions`.
- **`formatting()`** — Sets terminal globals (`BFR`, `HOLD`, `TAB`). Called by `load_functions`.
- **`icons()`** — Sets emoji/glyph message prefixes (`CM`, `CROSS`, `INFO` etc.). Depends on `TAB`/`CL`. Called by `load_functions`.
- **`default_vars()`** — Sets `RETRY_NUM=10`, `RETRY_EVERY=3`. Called by `load_functions`.
- **`set_std_mode()`** — Sets `$STD` to `"silent"` (normal) or `""` (when `VERBOSE=yes`). Called by `load_functions`, `install.func`.
- **`parse_dev_mode()`** — Reads `dev_mode` env var (comma-separated flags: trace, keep, pause, etc.), exports `DEV_MODE_*` booleans. Called by `build.func`.

### Validation — Exit 1 on failure

Each is called by `build.func` during `setup_script`:
- **`shell_check()`** — Abort if not running under Bash.
- **`root_check()`** — Abort if not root or running via sudo.
- **`pve_check()`** — Abort if PVE version outside supported range (8.0-8.9 or 9.0-9.2).
- **`arch_check()`** — Abort if not amd64.
- **`ssh_check()`** — Warn (not abort) if running over SSH.

### Logging & execution

- **`get_active_logfile()`** — Returns path to the active log file. Reads `_HOST_LOGFILE` > `INSTALL_LOG` > `BUILD_LOG` > fallback.
- **`strip_ansi()`** — Strips ANSI escape codes from stdin/args. Called by `log_msg`.
- **`log_msg()`** — Appends timestamped, ANSI-stripped line to the active log. Called by all `msg_*` helpers.
- **`log_section()`** — Writes a `=== Name ===` divider to the log. Called by `build.func`.
- **`silent()`** — Runs a command with stdout/stderr redirected to the log; on failure prints error + last 20 log lines and exits. This is what `$STD` resolves to unless `VERBOSE=yes`. Called via `$STD` from every helper that suppresses output.
- **`spinner()`** — Backgrounds a Braille spinner animation. Called by `msg_info`.
- **`clear_line()`** — Erases the current terminal line via `tput` or raw ANSI. Called by `msg_ok`.
- **`stop_spinner()`** — Kills the spinner process, tidies terminal. Called by every `msg_*` helper.

### Message output — Called from framework files and user scripts everywhere

- **`msg_info()`** — Prints a step-in-progress line + spinner. Reads `$1` (message).
- **`msg_ok()`** — Replaces spinner with green checkmark. Reads `$1` (message).
- **`msg_error()`** — Prints red error line. Reads `$1` (message). Does not exit.
- **`msg_warn()`** — Prints yellow warning line. Reads `$1` (message).
- **`msg_custom()`** — Prints `$1` (symbol) + `$2` (color escape) + `$3` (message).
- **`msg_debug()`** — Prints `[DEBUG]` line when `var_full_verbose=1`. Reads `var_full_verbose`.
- **`msg_dev()`** — Prints `[DEV]` line when `dev_mode` is non-empty.
- **`fatal()`** — Calls `msg_error` then `kill -INT $$` (triggers error trap).

### Utility

- **`exit_script()`** — Clears screen, prints "User exited script", exits.
- **`get_header()`** — Fetches an ASCII-art banner from the repo (cached locally). Reads `APP`, `APP_TYPE`.
- **`header_info()`** — Clears screen and prints the app banner. Reads `APP`. Called by `bootstrap/lxc`, all `scripts/` entry points.
- **`is_alpine()`** — Returns 0 if the host/container is Alpine. Reads `var_os`, `PCT_OSTYPE`, `/etc/os-release`.
- **`is_verbose_mode()`** — Returns 0 if `VERBOSE`/`var_verbose` is set or stderr not a TTY.
- **`is_unattended()`** — Returns 0 if no interactive prompts needed. Reads `MODE`, `PHS_SILENT`, `var_unattended`, TTY state.
- **`prompt_confirm()`, `prompt_input()`, `prompt_input_required()`, `prompt_select()`, `prompt_password()`** — Interactive whiptail-like prompts with unattended and timeout fallbacks. All use `is_unattended()`. Called by `build.func`, optionally available to user `install_script()`.

### Cleanup

- **`cleanup_lxc()`** — (core.func version) Package-cache cleanup (apt/apk, pip/uv/npm/yarn/pnpm/go/cargo/gem/composer). Errors tolerated. Called by `install.func` wrapper postamble. NOTE: `install.func` defines a competing `cleanup_lxc` that shadows this one (supports all OS families).
- **`check_or_create_swap()`** — Detects swap; offers to create `/swapfile`. Reads user input via `prompt_*`.
- **`get_lxc_ip()`** — Exports `LOCAL_IP`. Tries `/run/local-ip.env` then network probes.
- **`ensure_profile_dot_d()`** — Sources `/etc/profile.d/*.sh` to fix PATH in non-login shells.

---

## `misc/build.func` — LXC orchestration

### Bootstrap-invoked entry points

Called directly by `bootstrap/lxc` in order:

- **`variables()`** — Initializes per-session globals: `NSAPP` (lowercase, no spaces), `var_install` (`<nsapp>-install`), `SESSION_ID` (8-char random), `BUILD_LOG`, `RANDOM_UUID`, `PVEHOST_NAME`, `PVEVERSION`, `KERNEL_VERSION`. Captures `APP_DEFAULT_*` from `var_*`. Reads `APP`, `var_cpu`/`ram`/`disk`, `/proc/sys/kernel/random/uuid`, `hostname`, `pveversion`.
- **`start()`** — Context dispatcher. On Proxmox host (`pveversion` exists) → calls `setup_script` then returns. Inside existing container → runs update flow (`update_script` + `cleanup_lxc`). Reads `PHS_SILENT`, `SCRIPTS_URL`.
- **`build_container()`** — The LXC creation orchestrator. Stages: `pre_build_script` → `pct create` → `pct start` → base packages → compose/push wrappers → `lxc-attach` → check failure flag → `post_build_script`. Also pre-stages `/tmp/_update.sh` and `/tmp/_uninstall.sh`. Reads: every container-config global (`CT_ID`, `HN`, `BRG`, `NET`, `GATE`, `CORE_COUNT`, `RAM_SIZE`, `DISK_SIZE`, `PW`, `var_os`, `var_version`, `SCRIPTS_URL`, `SESSION_ID`, etc.). Writes wrapper files, runs `pct` commands.
- **`complete_install()`** — Finalization stage. Queries container IP, sets PVE web-UI description, runs `systemctl start ping-instances.service`, invokes `post_install_script` hook, prints final success message. Previously called `description`.

### Menu & settings

Called by `setup_script`:
- **`setup_script()`** — Host-side menu entry. Runs preflight checks, shows whiptail (Default / Advanced / User Defaults / App Defaults / Settings). Dispatches to matching settings function. Reads `env mode`, `NSAPP`, `PVEHOST_NAME`.
- **`base_settings()`** — Populates container-config globals from `var_*` defaults. Applies "higher wins" rule for CPU/RAM/disk. Validates ID, hostname, network, APT cacher. Sets `CT_TYPE`, `DISK_SIZE`, `CORE_COUNT`, `RAM_SIZE`, `CT_ID`, `HN`, `BRG`, `GATE`, `SD`, `NS`, `VLAN`, `MTU`, `TAGS`, all `ENABLE_*`, `CT_TIMEZONE`, etc. Input: `var_*` globals + `$1` (verbose override).
- **`advanced_settings()`** — 28-step whiptail wizard. Same globals as `base_settings` but user-filled. Each step validates input.
- **`default_var_settings()`** — Loads user defaults from `/usr/local/scripts-underground/default.vars`, runs `base_settings` + `echo_default`.
- **`echo_default()`** — Prints pre-creation summary. Reads all container-config globals.
- **`settings_menu()`** — Sub-menu: user defaults, app defaults, dev mode.
- **`dev_mode_menu()`** — Toggle dev mode flags.
- **`run_preflight()`** — Runs all `preflight_*` checks, prints summary, exits on failure.

### Preflight checks

Each reads a specific PVE resource and calls `preflight_pass`/`preflight_fail`/`preflight_warn`. Called by `run_preflight`:
- `preflight_maxkeys`, `preflight_storage_rootdir`, `preflight_storage_vztmpl`, `preflight_storage_space`, `preflight_network_bridge`, `preflight_dns_resolution`, `preflight_repo_access`, `preflight_cluster_quorum`, `preflight_lxc_stack`, `preflight_container_id`, `preflight_template_connectivity`, `preflight_template_available`.
- **`preflight_pass/fail/warn`** — Record result, increment counters. `preflight_fail` stores `exit_code|message` in `PREFLIGHT_FAILURES[]`.

### Validators

Pure functions returning 0/1, no side effects:
- `validate_container_id`, `get_valid_container_id`, `validate_hostname`, `validate_mac_address`, `validate_vlan_tag`, `validate_mtu`, `validate_ipv6_address`, `validate_bridge`, `validate_gateway_in_subnet`, `validate_ip_address`, `validate_gateway_ip`, `validate_timezone`, `validate_tags`, `is_ip_range`.
- Each reads `$1` (value to validate); returns 0 if valid.
- Called from `base_settings`, `advanced_settings`, `load_vars_file`.

### Defaults file management

- **`load_vars_file()`** — Saves whitelisted `var_*` from file into env. Validates each value. Reads `$1` file path, `$2` force flag.
- **`get_app_defaults_path()`** — Prints path to app-specific vars file (`/usr/local/scripts-underground/defaults/<nsapp>.vars`).
- **`maybe_offer_save_app_defaults()`** — After Advanced install, prompts to save current settings as app defaults.
- **`ensure_storage_selection_for_vars_file()`** — Ensures template and container storage vars exist in a file; prompts if missing.
- **`choose_and_set_storage_for_file()`** — Storage selection wizard for vars file creation.

### SSH

- **`find_host_ssh_keys()`** — Scans standard paths for SSH public keys. Sets `FOUND_HOST_KEY_COUNT`.
- **`ssh_extract_keys_from_file()`** — Filters a file to valid public key lines.
- **`ssh_build_choices_from_files()`** — Builds whiptail checklist entries from key files. Uses `ssh-keygen` for fingerprints.
- **`configure_ssh_settings()`** — Interactive SSH key selection flow. Sets `SSH_KEYS_FILE`, `SSH_AUTHORIZED_KEY`, `SSH`.
- **`install_ssh_keys_into_ct()`** — Pushes selected SSH keys into the container via `pct push`/`pct exec`.

### Networking

- **`resolve_ip_from_range()`** — Pings each address in an IP range, returns first non-responding one via `NET_RESOLVED`.
- **`ip_to_int()` / `int_to_ip()`** — Convert between dotted-quad and 32-bit integer.

### Storage

- **`check_storage_support()`** — Returns 0 if any PVE storage supports given content type.
- **`resolve_storage_preselect()`** — Validates a preselected storage name against `pvesm`.
- **`select_storage()`** — Interactive whiptail storage picker. Sets `STORAGE_RESULT`.
- **`validate_storage_space()`** — Confirms a storage has enough free space.
- **`create_lxc_container()`** — Core `pct create` driver. Template download/lookup, storage validation, `pct create` with retry/fallback, post-creation `post_build_script` call.

---

## `misc/install.func` — In-container install helpers

Text transported inside the install wrapper and sourced at container runtime.

### Bootstrap

- **`detect_os()`** — Identifies distro and sets `OS_TYPE`, `OS_FAMILY`, `OS_VERSION`, `PKG_MANAGER`, `INIT_SYSTEM`. Reads `/etc/os-release`, Alpine/Debian/RedHat release files.
- **_bootstrap()** (source-time side effect) — Ensures `curl` exists, sources `core.func` + `error_handler.func`, calls `catch_errors`, `get_lxc_ip`.

### Package manager abstraction — Used by install_script() authors

Each reads `PKG_MANAGER` (set by `detect_os`) and dispatches to the correct tool:
- **`pkg_update()`** — Refresh package index. Includes mirror failover for apt/apk.
- **`pkg_upgrade()`** — Upgrade all packages. `dist-upgrade` semantics for apt.
- **`pkg_install()`** — Install package(s). `$@` = package list. The canonical install primitive.
- **`pkg_remove()`** — Remove package(s).
- **`pkg_clean()`** — Purge package cache and orphans.

### Init system abstraction

Each dispatches based on `INIT_SYSTEM` (systemd / OpenRC / sysvinit):
- `svc_enable()`, `svc_disable()`, `svc_start()`, `svc_stop()`, `svc_restart()`, `svc_status()`, `svc_reload_daemon()`. Each takes `$1` = service name.

### Network & connectivity — Called by wrapper postamble

- **`get_ip()`** — Prints the container's primary IPv4 address (layered probes). Called by `setting_up_container`.
- **`verb_ip6()`** — Disables IPv6 if `IPV6_METHOD=disable`. First call in wrapper postamble.
- **`setting_up_container()`** — Baseline container setup: verify root ownership, wait for network, set UTF-8 locale, disable PEP 668 guard, work around Arch/ pacman Landlock. Exits 1 if no network.
- **`network_check()`** — Verify DNS resolution and internet connectivity. Injects fallback resolvers if broken resolver detected. May exit 1.

### OS update — Called by wrapper postamble

- **`update_os()`** — `pkg_update` + `pkg_upgrade`, then sources `tools.func` (or `alpine-tools.func`) so `fetch_and_deploy_*` etc. are available to `install_script()`.

### MOTD & SSH — Called by wrapper postamble

- **`motd_ssh()`** — Install scripts-underground MOTD, configure terminal size, optionally install/configure SSH for root login. Reads `SSH_ROOT`, `APPLICATION`.

### Container customization — Called by wrapper postamble

- **`setup_lxc()`** — Customize LXC: passwordless root, autologin gettys, disable services, install baked update/uninstall helpers, inject SSH key. Reads `PASSWORD`, `SSH_AUTHORIZED_KEY`.
- **`cleanup_lxc()`** — (install.func version, shadows core.func) — `pkg_clean()` + OS-agnostic cleanup.
- **`validate_tz()`** — Returns 0 if timezone exists in zoneinfo.
- **`set_timezone()`** — Apply timezone to the container.
- **`os_info()`** — Debug dump of OS detection globals.

### Wrapper postamble order (fixed in `build.func`)

```
verb_ip6 → setting_up_container → network_check → update_os → install_script → motd_ssh → setup_lxc → cleanup_lxc
```

---

## `misc/tools.func` — App helper library

~120 functions sourced indirectly by every LXC `install_script` via `update_os()` inside the wrapper. Grouped by role.

### Download primitives

- **`curl_with_retry()`** — Retry-safe HTTP download. `$1`=url, `$2`=output (default stdout). DNS pre-check, exponential backoff. Env: `CURL_RETRIES`, `CURL_TIMEOUT`.
- **`curl_api_with_retry()`** — HTTP GET with status code capture. Returns code to stdout, body to file.
- **`download_gpg_key()`** — Downloads and installs a GPG key to keyring path. Auto-detects armored/binary.
- **`download_with_progress()`** — `pv`-metered download.
- **`curl_download()`** — Speed-sensitive download for large files (no `--max-time`, uses `--speed-limit`).
- **`debug_log()`** — Prints `[DEBUG]` to stderr when `TOOLS_DEBUG=true`.

### OS / arch detection

- **`get_os_info()`** — Cached reader of `/etc/os-release` fields. Exports `_OS_ID`, `_OS_CODENAME`, `_OS_VERSION`, `_OS_VERSION_FULL`.
- **`get_system_arch()`** — Prints `amd64`/`arm64`.
- **`is_debian()`**, **`is_ubuntu()`**, **`is_alpine()`** — Boolean OS checks.
- **`get_os_version_major()`** — Major version from `VERSION_ID`.
- **`get_parallel_jobs()`** — Safe parallel job count (CPU + memory-aware).
- **`get_default_php_version()`**, **`get_default_python_version()`**, **`get_default_nodejs_version()`** — Version defaults for current distro.
- **`version_gt()`**, **`should_upgrade()`** — Version comparison utilities.

### APT / repository plumbing

- **`is_package_installed()`** — Cross-distro installed check.
- **`is_apt_locked()`**, **`wait_for_apt()`** — Lock detection and wait.
- **`ensure_apt_working()`** — APT recovery: configure interrupted ops, clean orphans, retry update. Returns 0 or 100.
- **`cleanup_old_repo_files()`**, **`cleanup_orphaned_sources()`**, **`cleanup_tool_keyrings()`** — Repository file cleanup per app name.
- **`prepare_repository_setup()`** — Runs cleanup pipeline before adding a repo.
- **`verify_repo_available()`** — HTTP HEAD probe of a repo's Release file (5-min cached).
- **`get_fallback_suite()`** — Applies codename fallback chain for third-party repos.
- **`setup_deb822_repo()`** — Writes standard deb822 `.sources` file, downloads GPG key, runs `apt update`.
- **`manage_tool_repository()`** — Tool-specific repo configuration (mariadb, mongodb, nodejs, php, postgresql, mysql). Reads tool name + version.
- **`ensure_dependencies()`** — Batch-install packages needed for a task. Checks PATH for binaries. 5-min `apt update` cache. Read: `$@` = dependency names. Called from almost every setup_* and many user scripts.
- **`install_packages_with_retry()`**, **`upgrade_packages_with_retry()`**, **`upgrade_package()`** — APT install/upgrade with progressive retry.
- **`hold_package_version()`**, **`unhold_package_version()`** — `apt-mark` wrappers.
- **`verify_package_source()`** — Checks `apt-cache policy` output.

### Services

- **`stop_all_services()`** — Stops and disables multiple services by pattern.
- **`safe_service_restart()`** — Restart with wait-for-ready loop.
- **`enable_and_start_service()`** — systemctl enable + start.
- **`is_service_enabled()`**, **`is_service_running()`** — systemctl status checks.

### Version tracking

- **`cache_installed_version()`** — Persists `app=version` to `/var/cache/app-versions/<app>_version.txt`.
- **`get_cached_version()`** — Reads back cached version.
- **`is_tool_installed()`** — Probes tool version and (optionally) compares against a target. Supports mariadb/mysql/mongodb/node/php/postgres/ruby/rust/go/clickhouse.
- **`should_update_tool()`** — Returns 0 if `installed != target`.
- **`verify_tool_version()`** — Compares major versions, warns on mismatch.
- **`cleanup_legacy_install()`** — Removes nvm/rbenv/rustup/gopath home-brew installations before installing official tool package.
- **`remove_old_tool_version()`** — Full uninstall: stop services, `apt purge`, remove data dirs, keyrings, legacy cleanups.

### Backup & restore (for `update_script()` authors)

- **`create_backup <path> [...]`** — Copies each path into a manifest-tracked store (default `/opt/<NSAPP>.backup`, override with `BACKUP_DIR`), mirroring absolute paths under `<store>/files`. Idempotent per path; missing paths and mount points are skipped with a warning; aborts the update on copy failure.
- **`restore_backup()`** — Restores every manifest-recorded path back to its origin (replacing whatever the update left), then deletes the store. No-op with a warning when no store exists.

Typical update flow: `create_backup /opt/app/.env /opt/app/data` before the upgrade; call `restore_backup` on the failure path. The store name falls back to `$APP_SLUG` when `$NSAPP` is unset (addon bundles).

### GitHub / Codeberg / GitLab API

- **`validate_github_token()`** — Tests PAT against GitHub `/user`. Returns 0/1/2/3.
- **`prompt_for_github_token()`** — Interactive PAT entry; exports `GITHUB_TOKEN`.
- **`github_api_call()`** — Authenticated GET with rate-limit backoff. Reads `GITHUB_TOKEN`.
- **`codeberg_api_call <url> [output_file] [status_file]`** — Codeberg API GET (no auth needed). The optional third file records the final HTTP status; incomplete or curl-failed transfers record `000`. The existing two-argument/stdout interface and error codes remain supported.
- **`get_latest_gh_tag()`**, **`get_latest_github_release()`**, **`get_latest_codeberg_release()`**, **`get_latest_gitlab_release()`** — Latest version probes.
- **`extract_version_from_json()`** — `jq` field extraction from release JSON.

### Version comparators (for update_script authors)

Each compares latest against cached version and sets `CHECK_UPDATE_RELEASE`:
- **`check_for_gh_tag()`** — Compare latest GitHub tag. `$1`=app, `$2`=repo, `$3`=tag prefix.
- **`check_for_gh_release()`** — Compare latest GitHub release. Supports pinned versions. 28+ callers in `scripts/lxc/`.
- **`check_for_codeberg_release()`**, **`check_for_gl_release()`** — Same contract for Codeberg/GitLab.

### Release fetch & deploy

- **`fetch_and_deploy_gh_tag()`** — Download tag archive via `refs/tags/<tag>.tar.gz`, extract to target. Modes: tag-only repos.
- **`fetch_and_deploy_gh_release()`** — Workhorse deployer. Modes: `tarball`/`binary`/`prebuild`/`singlefile`. 62+ callers in user scripts. Handles arch-matched `.deb` search with older-release fallback. `FORCE_DEPLOY=1` explicitly redeploys the selected release without changing its version marker; normal same-version calls remain idempotent.
- **`fetch_and_deploy_codeberg_release()`**, **`fetch_and_deploy_gl_release()`** — Same contract for Codeberg/GitLab.
- **`fetch_and_deploy_from_url()`** — Plain URL download with archive-type auto-detection and extraction.
- **`verify_gpg_fingerprint()`** — Compares keyring fingerprint against expected value.

Codeberg pins prefer the exact tag endpoint. Only a completed HTTP 404 permits
the alternate numeric-v spelling (`1.0.0` ↔ `v1.0.0`). Authentication,
rate-limit and incomplete-transfer failures do not trigger that fallback.
Explicit metadata must match the requested tag or its permitted equivalent;
raw tags such as `version/2` remain intact and URL-encoded. Selection and
already-current comparisons do not depend on the first release-list page.
Agreement is checked against raw JSON strings inside jq before Bash extraction.
Forbidden control/whitespace metadata rejects with250; valid slash/non-ASCII
spellings remain intact. Trailing newlines cannot turn a different raw tag into
an accepted requested pin, and stale selection/installed markers stay protected.

#### Archive transaction and retained recovery data

Codeberg `tag`, `tarball`/`source`, `prebuild`, and GitHub **prebuild** use one
private archive transaction owner. Public positional signatures are unchanged.
The canonical root is never renamed away; root binds, descendant directory
mounts and their ancestor skeletons remain attached. Ordinary files inside a
mounted directory can be replaced in their actual parent. Mounted-file
collisions, conflicting aliases, changed directory-link ancestors, unsupported
incoming links/special entries, and changed/pruned hardlinked files reject
before application. An existing internal leaf alias receiving regular data
keeps its link text while publication addresses the ordinary internal referent.

The complete incoming payload is extracted and validated before application.
Original overwritten/pruned leaves and the old marker are prepared before the
first live operation. JSON intent records precede individual prunes, directory
creations and same-parent leaf publication. The marker is published last through
the same protocol, then verified with the payload before `COMMITTED` is written.
Merge mode retains unrelated data; `CLEAN_INSTALL=1` prunes eligible absent
entries under non-hidden root names, preserves absent root dot entries, and
never prunes inside a proper descendant mount. Existing directories retain
their permissions, existing regular leaves retain owner/mode, and new files
take source mode subject to the caller's umask. No live directory is recursively
removed by this transaction.

Cooperating archive calls serialize on a stable lock in the executing guest's
`/var/lib/scripts-underground/release-deploy` (120-second acquisition bound).
Unique `txn-*` directories retain manifests, plans, operation state and
originals after commit or rollback. There is no automatic backup pruning or
store-path override. Unfinished records are validated and recovered before a
same-version shortcut. Invalid records or incompatible boot/mount-namespace or
mount topology changes refuse new mutation and identify the retained path.

Returned errors and caught INT/TERM cause reverse rollback under that lock.
Restoration copies retained originals to fresh same-parent candidates rather
than consuming backups. If a live entry matches neither the original nor the
transaction's expected result, preserve it and the backup, report
`RECOVERY_REQUIRED`, and continue independent safe undo steps. Recovery trouble
does not become successful deployment; an on-disk committed decision is never
undone by a later cleanup failure. Disposable cleanup problems after commit are
warnings. Caller EXIT/INT/TERM traps remain caller-owned.

Journal publication requires a completed successful producer and exactly one
complete JSON document with the caller's required record shape. Empty,
multiple-document and truncated input cannot replace the previous valid
destination. A producer that emits valid bytes but exits nonzero cannot
authorize publication; this contract is independent of caller pipefail/errexit.
Schedule readers complete and validate cardinality, row types and expected
counts before their rows are consumed. A failed reader or partial prefix is not
a successful empty verification/undo. Scalar/path reads retain trailing
newlines and check the producer's status before assigning the value.

Current finalization requires validated committed records and checked actual
payload/marker readback, or an explicit recovered same-version no-op, before
returning success. Returning status 0 followed by rollback is still a deployment
failure. A valid committed publication remains accepted if its rename reports
a later error; failed decision/outcome reads are reported as failure rather
than downgraded to disposable-cleanup warnings. Historical journal validation
does not create reader artifacts inside those retained records.

New manifest, decision, operation and fingerprint records use **schema 2**.
The decision records monotone `application_started`, complete `plan_count`,
and sealed plan/alias SHA-256 values. `APPLYING` authorizes application only
after every planned original/input and operation has been validated. Once true,
`application_started` is never reset. Application-capable phases require the
entire sealed record set; missing plan, alias or operation data is invalid
recovery, not an empty undo schedule. Historical completed decisions are
structurally inspected without comparing them to a later legitimate live
generation. Unknown or contradictory records refuse mutation.

Decision and operation writers validate the complete candidate shape before its
rename and check the legal predecessor. Completed decisions cannot return to
application, and applied operations cannot return to preparation. Recovery may
repeat its restoring steps and finalize directory metadata under `ROLLING_BACK`;
these retries do not reopen a committed or rolled-back decision. Rejected
candidates leave the previous valid document intact.

Record inspection uses a record-local context. It cannot change the current
request's target, marker, input root, fingerprint revision, root identity or plan
seals. Recovery and finalization explicitly load a validated record's context;
the loader assigns that context only after all required reads succeed.

New schema-2 manifests declare `fingerprint_revision: 2`, requiring exact native
UTC nanosecond leaf mtime alongside bytes, owner, mode and the complete native
attribute set. An unchanged symlink referent does not make a timestamp-only link
edit safe to overwrite. Historical schema-2 records without this declaration
retain revision-1 comparisons; unknown revisions and malformed extensions refuse
mutation. Historical records are not rewritten to fabricate timestamps.

Private Boolean readers distinguish a successfully read false value from producer
failure. Checked record writers/loaders return 0 on success and 252 on rejection
or failed reads; shape predicates return the completed jq predicate status, which
their callers must check. These conventions do not change public provider status
codes or transfer service ownership from callers into the engine.

Initialization allocates a private retained `init-*` directory, prepares and
validates its complete bootstrap plus a preallocated preparation-only terminal
decision, then publishes its unused `txn-*` name. Unpublished allocations never
authorize application or become active recovery records; failed allocations
remain evidence without poisoning unrelated later calls. Aliases publish before
the plan. PREPARING/false may contain a valid PREPARED prefix and a partial next
copy, but never application progress/candidates. A checked preparation abort
verifies unchanged planned originals and renames the preallocated ROLLED_BACK/
false decision without allocating a new state temporary into a full store.
Incomplete legacy application recovery is refused rather than guessing stronger
original/ownership evidence from current live data.
The schema1 dispatcher requires a complete structurally usable record set for
completed history. Fully initialized PREPARING with a valid exclusive PREPARED
prefix/no candidates can terminate without application changes; its checked
schema1 terminal decision records `preparation_only:true`, preserving every
legacy artifact. Missing files alone never establish that proof. Unsafe active
schema1 application/recovery remains explicitly refused at its exact retained
path because it lacks the new ownership/directory-original guarantee; new
finalization cannot enter the former permissive recovery branch. Completed
history is neither rewritten nor recertified as schema2 metadata evidence.

Recovery rechecks PREPARED and already-RESTORED originals. A later edit to a
RESTORED object is a conflict even if it matches the former incoming value;
it does not authorize restoring again or starting a new deployment. Independent
safe undo may continue, but ROLLED_BACK requires a complete checked original/
alias/root/mount outcome, including untouched PREPARED operations. Completed
historical generations are not compared against later legitimate live bytes.

Physical exclusion covers effective roots and proper descendant mount origins
of target, prepared input and store, plus each changed entry and same-parent
candidate. Explicit kernel mount parentage resolves visible stacked attachments;
hidden/ambiguous mappings reject rather than choosing an arbitrary mount row.
Store-covering/descendant attachments participate in topology guards.
Prepared-tree source roots are recorded as `input_root` and their covering/
descendant attachments are checked during preparation and recovery; owned
archive staging is covered by the store's topology guard. The lock
opens without truncating its contents; held descriptor and pathname must retain
the same device/inode/type/owner/link count, and the store identity is guarded.
An archive owner never unlinks, replaces or repairs that lock inode.

Each locked call allocates a separate private `.read-*` workspace before prior
journal inspection. Its fixed native-output/diagnostic/canonical-body buffers
and checksum checkpoint are allocated once and reused serially, including
fingerprint subshells. Completed checked native getfattr output is accepted only
with no diagnostics and valid exactly-one-object framing (or the characterized
successful empty set); duplicate names, missing separators, NUL bytes and
partial/multiple/failed producers reject. Encoded names/hex values remain in
canonical files rather than binary Bash/JSON values. Historical journal reads
never create those buffers inside retained records.

Reader directory/buffer identity, ownership, link count, current content and
native metadata govern cleanup. Only known owned disposable buffers are
unlinked; replacements, hardlinks, unexpected entries/edits or ambiguous
initialization retain the workspace. Older reader leftovers are not recovery
authorities or adopted cleanup targets. Reusing allocated buffers supports the
bounded preparation ENOSPC case; it is not an arbitrary-growth-on-full-storage
guarantee. Standard attr (`getfattr`/`setfattr`) is a transaction prerequisite.

Schema-2 non-absent fingerprints include the full canonical xattr-set SHA-256
and count, including access/default ACLs exposed by the native utility.
Allocation identity and link count are distinct from content/basic metadata.
New-directory preparation records only the requested mode with
`metadata_pending`; native mkdir's actual inherited group/setgid/default-ACL
fingerprint and identity replace that request before APPLIED. Caught INT/TERM
are deferred through a bounded immune primitive child until actual creation
and ownership observation finish; the single owner's pending130/143 remains
authoritative and caller traps stay isolated.

Operation `attempts` replace string temporaries/shared per-purpose fingerprints.
Each attempt records canonical purpose/number/path, guarded parent/directory,
retained source fingerprint/size, exclusive candidate identity/initial metadata,
copy result/status, readiness and cleanup state. Regular data copies into a
preallocated inode do not preserve attributes; full data/prefix/identity and
initial metadata observations establish ownership even after a genuine copy
error. Attributes are then applied and verified separately. Links use literal
exclusive creation and no dereferenced placeholder copy. Later attempts cannot
lend ownership to earlier partials. Unexpected bytes/mode/ACL/xattrs/inodes/
hardlinks retain their conflicts and gate retry. Verified attempts are cleared
before their created parent is removed via rmdir.

Prepared pruned-directory originals retain a nonrecursive GNU pax archive,
verified empty metadata replica, complete native attribute body/hashes and an
independent zero-byte native timestamp reference. Replica identity/ctime,
archive/body consistency and guarded references are validated; no populated
installed directory is recursively cloned. GNU tar ACL/xattr/no-recursion
capabilities are mandatory before mutation. Directory restoration recreates
owned parents, restores children and clears attempts first, then applies the
empty replica's attributes, reconciles only attributable extra attributes,
regenerates the guarded native restore header and restores timestamps last.
Only fresh full-set/mode/owner/result verification authorizes RESTORED.
Archives are never extracted over populated live data. No inode/ctime restore
claim is made. Retained intermediate aliases protect every ordinary ancestor
skeleton while eligible obsolete siblings remain prunable.

This is **per-entry publication**, not whole-tree visibility atomicity. Callers
still stop services/quiesce noncooperating writers; readers may see mixed
generations during application/rollback. There is no SIGKILL, power-loss or
hostile concurrent-root race guarantee. The transaction returns 250 for
download failure, 251 for extraction failure, 252 for deployment/preparation or
recovery failure, 65 for unsupported input, and preserves caught 130/143.
GitHub's existing `FORCE_DEPLOY` flag forces its prebuild application; Codeberg
has ordinary idempotence and no new force-variable API. GitHub source/tarball,
package installs, generic backup/restore and the full RomM build/database flow
have their existing distinct guarantees.

### Runtime setups — Each reads version from env, installs, caches version

- **`setup_adminer()`** — Install Adminer PHP web UI.
- **`setup_clickhouse()`** — Install/upgrade ClickHouse via official repo or GitHub. Reads `CLICKHOUSE_VERSION`.
- **`setup_composer()`** — Install/self-update PHP Composer.
- **`setup_docker()`** — Install/upgrade Docker (distro packages or official repo). Optional Portainer. Reads `USE_DOCKER_REPO`, `DOCKER_PORTAINER`.
- **`setup_ffmpeg()`** — Install FFmpeg (static binary or source build). Reads `FFMPEG_VERSION`, `FFMPEG_TYPE`.
- **`setup_go()`** — Install Go from official tarball. Reads `GO_VERSION`.
- **`setup_gs()`** — Install Ghostscript from source.
- **`setup_imagemagick()`** — Build ImageMagick 7 from source.
- **`setup_java()`** — Install Temurin JDK via Adoptium repo. Reads `JAVA_VERSION`.
- **`setup_mariadb()`** — Install/upgrade MariaDB (distro packages or official repo). Reads `MARIADB_VERSION`.
- **`setup_mariadb_db()`** — Provision database + user. Reads `MARIADB_DB_NAME`/`USER`/`PASS`. Exports DB vars.
- **`setup_meilisearch()`** — Install/upgrade MeiliSearch. Dump/restore migration for major upgrades.
- **`setup_mongodb()`** — Install/upgrade MongoDB. AVX check. Reads `MONGO_VERSION`.
- **`setup_mysql()`** — Install/upgrade MySQL (distro packages or official repo). Reads `MYSQL_VERSION`.
- **`setup_nodejs()`** — Install/upgrade Node.js via NodeSource. Reads `NODE_VERSION`. Computes safe heap limit.
- **`setup_php()`** — Install PHP + modules (Sury repo). Reads `PHP_VERSION`, `PHP_MODULE`, `PHP_APACHE`/`PHP_FPM`.
- **`setup_postgresql()`** — Install/upgrade PostgreSQL (distro packages or PGDG repo). Pre-upgrade dump/restore. Reads `PG_VERSION`, `PG_MODULES`.
- **`setup_postgresql_db()`** — Provision role + database. Reads `PG_DB_NAME`/`USER`/`PASS`. Exports DB vars.
- **`setup_ruby()`** — Install rbenv + ruby-build. Reads `RUBY_VERSION`, `RUBY_INSTALL_RAILS`.
- **`setup_rust()`** — Install rustup + toolchain + crates. Reads `RUST_TOOLCHAIN`, `RUST_CRATES`.
- **`setup_uv()`** — Install `uv` (astral-sh) binary. Selects explicit `UV_VERSION`, then the effective exact project pin, then latest. A present `uv.toml` masks pyproject settings even when its root-level pin is absent/non-exact; otherwise only direct `[tool.uv]` is inspected. Reads `USE_UVX`, `PYTHON_VERSION`; requested Python installations are also handled when uv is already at the selected version.
- **`setup_yq()`** — Install/update `mikefarah/yq`.
- **`setup_nltk()`** — Download NLTK data packages.
- **`setup_nonfree()`** — Enable Debian non-free repositories.
- **`setup_hwaccel()`** — GPU passthrough for the container. Detects GPU, dispatches to Intel/AMD/NVIDIA setup. Reads `ENABLE_GPU`, `INSTALL_NVIDIA_DRIVERS`.

The shell-based uv extractor supports ordinary single-line basic/double or
literal/single quoted `required-version` values, horizontal whitespace, and a
comment after the closing quote. It tracks tables and unrelated quoted/multiline
text, preserves internal `#`, and does not claim general TOML compliance.
Bare numeric version tokens and complete `==` requirements select exact tags;
wildcards/compound ranges retain latest fallback rather than becoming exact.
Recognized complete `==...` explicit overrides normalize to the version before
comparison/download/cache; other explicit override spellings retain their
existing interpretation and precedence. Escaped/multiline targeted values,
invalid types, duplicate settings and unsupported targeted syntax return an
actionable parse error, not a latest installation. Private parser statuses are
0 = exact version on stdout, 1 = absent/non-exact, 2 = invalid/unsupported;
`setup_uv` maps status 2 to 250. Diagnostics go to stderr. No production
Python/TOML parser dependency is introduced and ranges are not resolved.
LF and CRLF records use the same lexical path: only a terminal record-ending CR
is removed before header/target parsing. Quoted/interior data is not stripped or
rewritten; effective-file precedence, exact/range handling and status mapping
remain unchanged.

### Utilities

- **`check_available_storage_bytes(bytes, path...)`** — Pre-mutation available-byte guard. It resolves each absolute path's nearest existing directory ancestor, checks completed GNU stat/df observations, and deduplicates filesystem device identities. Missing/invalid/incomplete command output fails closed; it creates no directories and never prompts or removes data. Returns 0 for sufficient space, 65 for invalid input and 252 for unavailable/insufficient observation. The caller supplies its workload budget and paths; this utility has no application-specific policy.
- **`create_self_signed_cert()`** — Generate 2048-bit RSA cert with SANs.
- **`ensure_usr_local_bin_persist()`** — Persist `/usr/local/bin` in PATH across login/non-login shells.
- **`setup_local_ip_helper()`** — Install networkd-dispatcher hook for dynamic IP tracking.
- **`create_temp_dir()`** — `mktemp -d` with cleanup trap.

---

## `misc/error_handler.func` — Error traps

- **`catch_errors()`** — Enables `set -Ee -o pipefail`, installs ERR/EXIT/INT/TERM/HUP traps. Called by `bootstrap/lxc`, `build.func`, wrapper preamble.
- **`error_handler()`** — ERR-trap handler. Prints error info, writes container failure flag, may offer to destroy broken LXC. Reads exit code from `$1`/`$?`, command from `$2`/`$BASH_COMMAND`.
- **`on_exit()`** — EXIT-trap handler. Stops orphaned container, cleans lockfile.
- **`on_interrupt()`** — SIGINT handler. Stops LXC, exits 130.
- **`on_terminate()`** — SIGTERM handler. Stops LXC. Exits 143.
- **`on_hangup()`** — SIGHUP handler. Stops LXC. Exits 129.
- **`explain_exit_code()`** — Maps numeric exit code to description for all framework codes, shell codes, tool codes, PVE custom codes (200-231), validation codes (103-110), DB codes, Node.js (239-249). Relocated from `api.func`.
- **`_stop_container_if_installing()`** — (internal) Stops LXC mid-install to prevent overwriting failure records.

---



---

## `misc/vm.func` — VM creation helpers

Not wired into any bootstrap; VM architecture is TBD per `architecture.md §3.4`:

- **`vm_init_colors()`** — Sets ANSI color globals for VM-side output.
- **`vm_validate()`** — Asserts Proxmox host, root, amd64. Exits 1 on failure.
- **`vm_select_storage()`** — Whiptail storage picker for VM images. Sets `STORAGE`.
- **`vm_download_image()`** — Downloads VM disk image from `VM_URL`. Sets `VM_FILE`.
- **`vm_create()`** — Creates VM via `qm create`, imports disk, attaches storage.
- **`vm_start()`** — Sets cloud-init credentials, boots VM.
- **`vm_wait_for_ssh()`** — Polls SSH until connection succeeds or timeout.
- **`vm_inject_install()`** — SSHes into VM and runs `install_script` via `declare -f` pipe.
