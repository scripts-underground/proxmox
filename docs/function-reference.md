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

- **`get_active_logfile()`** — Returns path to the active log file. Reads `_HOST_LOGFILE` > `INSTALL_LOG` > `BUILD_LOG` > `${TMPDIR:-/tmp}/build-<timestamp>.log` fallback.
- **`strip_ansi()`** — Strips ANSI escape codes from stdin/args. Called by `log_msg`.
- **`log_msg()`** — Appends timestamped, ANSI-stripped line to the active log. Called by all `msg_*` helpers.
- **`log_section()`** — Writes a `=== Name ===` divider to the log. Called by `build.func`.
- **`silent()`** — Runs a command in the calling shell with stdout/stderr redirected to the active log and returns its exact status. Restores caller `set` options and ERR trap; command variable/cwd/umask effects remain. Pipelines observe caller pipefail. Handled failures can retry without diagnostics or stale global error context; unhandled failures reach the existing ERR/errexit handler. Normal Bash conditional/function status rules apply: unchecked `required && next` is not fatal sequencing; conditional consumers must explicitly propagate failures. `$STD` still selects this helper only in quiet mode; verbose remains direct passthrough.
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

### Update runner

- **`run_update_script [--clean]`** — Runs the `update_script` hook and always exits. Writes the per-app pending flag `/var/lib/scripts-underground/update-pending/<NSAPP|APP_SLUG>` before the hook; `on_exit` removes it only when the run exits 0. An existing flag or `--clean` exports `UPDATE_FORCE=1 FORCE_DEPLOY=1`. Other options exit 65. Called by `lxc_setup` and the LXC/addon update bundles.

### Cleanup

- **`cleanup_lxc()`** — Single shared implementation for package/language caches. Uses `pkg_clean` when available (all supported OS families), otherwise the existing apk/apt fallback; retains pip/uv/npm/yarn/pnpm/go/cargo/gem/composer cache behavior. Never recursively deletes arbitrary TMPDIR/shared temporary contents by filename; lifecycle owners remove their own stages. Installs call it in their postamble; `on_exit` calls it once for successful `run_update_script` runs, including explicit exit and no-op/no-new-release success. Package cleanup including applicable autoremove still runs for no-op success. An explicit call by the hook acknowledges that due cleanup, avoiding a second EXIT call. Noncritical update cleanup cannot replace original status or recurse through EXIT.
- **`check_or_create_swap()`** — Detects swap; offers to create `/swapfile`. Reads user input via `prompt_*`.
- **`get_lxc_ip()`** — Exports `LOCAL_IP`. Tries `/run/local-ip.env` then network probes.
- **`ensure_profile_dot_d()`** — Sources `/etc/profile.d/*.sh` to fix PATH in non-login shells.

---

## `misc/build.func` — LXC orchestration

### Bootstrap-invoked entry points

Called directly by `bootstrap/lxc` in order:

- **`variables()`** — Initializes per-session globals: `NSAPP` (lowercase, no spaces), `var_install` (`<nsapp>-install`), `SESSION_ID` (8-char random), `BUILD_LOG`, `RANDOM_UUID`, `PVEHOST_NAME`, `PVEVERSION`, `KERNEL_VERSION`. Captures `APP_DEFAULT_*` from `var_*`. Reads `APP`, `var_cpu`/`ram`/`disk`, `/proc/sys/kernel/random/uuid`, `hostname`, `pveversion`.
- **`start()`** — Context dispatcher. On Proxmox host (`pveversion` exists) → calls `setup_script` then returns. Inside existing container → runs update flow (`update_script` + `cleanup_lxc`). Reads `PHS_SILENT`, `SCRIPTS_URL`.
- **`build_container()`** — The LXC creation orchestrator. Stages: `pre_build_script` → `pct create` → `pct start` → base packages → compose/push bundles → `lxc-attach` → check failure flag → `post_build_script`. Host staging/logs use `${TMPDIR:-/tmp}`. Optional baked `var_lxc_tmpdir` selects and creates the receiver's separate temporary root; push/execution and in-place retry use that same path. Creator TMPDIR is never implicitly transported. Reads container-config globals (`CT_ID`, `HN`, `BRG`, `NET`, `GATE`, `CORE_COUNT`, `RAM_SIZE`, `DISK_SIZE`, `PW`, `var_os`, `var_version`, `SCRIPTS_URL`, `SESSION_ID`, etc.). Persistent update/uninstall bundles go directly to `/usr/local/sbin`.
- **`_prepare_container_bundles(path)`** — Checked normal/repair preparation for receiver root, install/update/uninstall bundles and command aliases. In-place repair callers report preparation failure and preserve the selected existing container instead of re-entering host error-handler removal.
- **`_validate_lxc_tmpdir(path)` / `_prepare_lxc_tmpdir(path)`** (`bundle.func`) — Shared receiving-context contract. Empty selects the unchanged default; explicit values are absolute, non-root normalized paths without control separators. Bash component checks reject symlinks before creation, without GNU realpath options. Missing intermediate components use0755; only the selected leaf uses shared sticky01777. Existing metadata is preserved and must allow intended app users to traverse/write. Runs before library/log effects at every invocation. Bad input returns65; filesystem errors keep their status.
- **`_write_bundle()` / `build_bundle()`** (`bundle.func`) — Explicitly checked linear producer and owned sender/receiver staging boundary. Generation failure removes its private stage and never pushes partial generated bytes. Receiving mktemp, push, chmod and atomic rename retain exact failure status, preserve the previous command and remove owned stages, including under conditional callers. Publication is per command, not a multi-bundle transaction.
- **`_addon_bundle_contents()` / `_addon_bundle_write()`** (`addon_lxc.func`) — Checked addon serializer and private same-filesystem publication owner. Generation, write, chmod, alias and rename failures remove the owned stage and preserve the previous valid command; complete executable bytes publish by atomic rename. Both addon/LXC uninstall bundles invoke the hook normally under existing ERR/EXIT handling, never conditionally; cleanup of commands/marker follows only a successful return.
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
- **_bootstrap()** (source-time side effect) — Retains the existing curl/transport baseline, initializes existing core/error APIs and fetches only missing libraries. Already inlined bundles keep their frozen handlers online/offline. Calls `load_functions`, `catch_errors`, `get_lxc_ip`.

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
- **`svc_prepare_uninstall(service, action?, was_running_var?)`** — Uninstall-only checked service preparation; default `disable` stops/disables as needed, `stop` retains shared-service registration. Optional caller-owned scalar output is `yes`/`no`; helper-local namespace `_svc_` is reserved, ordinary names such as `state` work. Completed systemd properties distinguish not-found inactive/failed tombstones from removed-file running units that still require stop. Known bad-setting/error load and empty/bad unit-file states allow applicable checked control; missing properties/unknown values fail22. OpenRC uses completed service/state queries and all verified `rc-update show` registration columns, deleting each matched runlevel before init-file removal. Query/control errors retain exact status and diagnostics; unsupported init intentionally returns1, invalid service/action/output65. Plain hooks retain data/commands/markers on failure. Other init APIs preserve their existing semantics.

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
- **`cleanup_lxc()`** — Provided by `core.func`; this file supplies the `pkg_clean` package-manager boundary, not an override.
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
- **`curl_api_with_retry()`** — HTTP GET with status code capture. `$1`=url, `$2`=optional body file, `$3`=extra curl options split on whitespace (no quoting). Prints the code to stdout, preceded by the body when no file is given. Returns 0 on 2xx, 7 after `CURL_RETRIES` attempts. Env: `CURL_RETRIES`, `CURL_TIMEOUT`, `CURL_CONNECT_TO`.
- **`download_gpg_key(url, output, mode?)`** — Downloads privately, processes/validates the public key with real GPG, and atomically publishes a same-filesystem stage. Auto-detects armored/binary; retains explicit modes. Returns0 on success,7 on failure. Transfer, processing, validation, metadata or publication failure preserves the last-known-good key; existing mode/owner are retained, new keyrings use0644.
- **`download_with_progress()`** — `pv`-metered download.
- **`curl_download()`** — Speed-sensitive download for large files (no `--max-time`, uses `--speed-limit`).
- **`debug_log()`** — Prints `[DEBUG]` to stderr when `TOOLS_DEBUG=true`.

### OS / arch detection

- **`get_os_info()`** — Cached reader of `/etc/os-release` fields. Exports `_OS_ID`, `_OS_CODENAME`, `_OS_VERSION`, `_OS_VERSION_FULL`.
- **`get_system_arch(source=dpkg, amd64_alias?, arm64_alias?)`** — Retains dpkg/default and normalized uname/both output; optional caller-selected release aliases map amd64/arm64 only, e.g. `get_system_arch both x64 aarch64`. Other detected architecture names retain their existing behavior.
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
- **`codeberg_api_call()`** — Codeberg API GET (no auth needed).
- **`get_latest_gh_tag()`**, **`get_latest_github_release()`**, **`get_latest_codeberg_release()`**, **`get_latest_gitlab_release()`** — Latest version probes.
- **`extract_version_from_json()`** — `jq` field extraction from release JSON.

### Version comparators (for update_script authors)

Each compares latest against cached version and sets `CHECK_UPDATE_RELEASE`. With `UPDATE_FORCE=1` (set by `run_update_script`) a matching version is reported as due:
- **`check_for_gh_tag()`** — Compare latest GitHub tag. `$1`=app, `$2`=repo, `$3`=tag prefix.
- **`check_for_gh_release(app, repo, pin?, reason?, prefix?)`** — Compare a checked GitHub selection. Explicit pin wins; optional stable prefix limits latest selection using raw `startswith` (include `v` and a separator, e.g. `v1.2.`, to exclude `v1.20.0`). Returns0 when due,1 when unchanged, other status on error; CHECK_UPDATE_RELEASE contains the raw tag only when due. Default designated latest, unfiltered semver-tag fallback when no stable release exists, own legacy marker and UPDATE_FORCE behavior are retained. Failures end the owned spinner and provide diagnostics without exposing tokens.
- **`check_for_codeberg_release()`**, **`check_for_gl_release()`** — Same contract for Codeberg/GitLab.

### Release fetch & deploy

- **`fetch_and_deploy_gh_tag()`** — Download tag archive via `refs/tags/<tag>.tar.gz`, extract to target. Modes: tag-only repos.
- **`fetch_and_deploy_gh_release(app, repo, mode?, version?, target?, asset?, prefix?, selected_json_file?)`** — Modes: `tarball`/`binary`/`prebuild`/`singlefile`. Uses private completed/parsed metadata; latest asset fallback stays in the optional raw tag-prefix and cannot replace an explicit pin. Older-asset fallback uses one checked request for at most15 releases, in API order; complete pagination remains for uv/prefix enumeration. The optional caller-owned JSON output is cleared at entry, filled on success with the actual selected object, and survives optional subshell calls without shared state. FORCE_DEPLOY, same-version idempotency and checked-copy/marker protections remain.
- **`_github_release_request(url, body_file, status_var)` / `_gh_release_json(repo, version, prefix, selected_file)`** — Small internal request/selection and private response ownership boundaries. Check transfer status and JSON before use; retain token recovery in the calling shell. Version getter, checker and deployer share selection instead of separate unchecked response paths.
- **`_resolve_igc_tag(outvar, selected_json_file)`** — Resolve the compiler tag from the explicitly supplied selected compute-runtime release, clearing output when absent/unusable. No shared-file lookup. Callers own/remove the metadata file; no hardware policy change.
- **`fetch_and_deploy_codeberg_release()`**, **`fetch_and_deploy_gl_release()`** — Same contract for Codeberg/GitLab.
- **`fetch_and_deploy_from_url()`** — Plain URL download with archive-type auto-detection and checked extraction, then the same replacement/persistence helper as release/source providers. Failed extraction never clears the target.
- **`_deploy_replace_contents(source, target, clean)`** — Checked shared source/archive replacement. Legacy `CLEAN_INSTALL_KEEP` stays a space-separated string; optional indexed Bash array `CLEAN_INSTALL_KEEP_PATHS=('database/custom name.sqlite' 'database/custom name.sqlite-wal')` adds lossless normalized relative paths. Existing keeps/links/mounts stay in place; missing keeps can receive defaults. Invalid paths fail65 before effects, deployment failures252 prevent marker advancement, and incompatible merge types fail before live effects. Source-only archive hardlink projection has independent directories and checked copy fallback. Existing merge/dot-merge directories retain identity/mode; only incoming replaced leaves/new directories move/copy in bounded batches with associative lookups. Old-only live subtrees are never projected/copied/moved/traversed. Failed publication removes only attempted planned leaves/empty new directories and preserves unrelated writers. Restore batches require absent destination names, use checked no-clobber moves and retain/report a conflicting aside. Fresh mountinfo containment checks before every owned recursive tree removal retain/report newly mounted stages/asides. Input bytes/mode/owner/mtime and target-root mode/owner remain preserved.
- **`verify_gpg_fingerprint()`** — Compares keyring fingerprint against expected value.

### Runtime setups — Each reads version from env, installs, caches version

- **`setup_adminer()`** — Install Adminer PHP web UI.
- **`setup_clickhouse()`** — Install/upgrade ClickHouse via official repo or GitHub. Reads `CLICKHOUSE_VERSION`.
- **`setup_composer()`** — Install/self-update PHP Composer.
- **`setup_docker()`** — Install/upgrade Docker (distro packages or official repo). Optional Portainer. Reads `USE_DOCKER_REPO`, `DOCKER_PORTAINER`.
- **`setup_ffmpeg()`** — Install FFmpeg (static binary or source build). Reads `FFMPEG_VERSION`, `FFMPEG_TYPE`.
- **`setup_go()`** — Install Go from official tarball. Explicit `GO_VERSION` retains priority and its existing selection. Optional `GO_PROJECT_DIR` treats numeric go and toolchain directives as minimums: preserve an installed stable satisfying both, otherwise select the latest available stable patch of the required minor from checked official JSON/architecture metadata. Actual pre1.21 initial tags without .0 are supported. Missing/malformed/duplicate project requirements fail65; failed/incomplete metadata or no matching release fails250 without global-latest fallback. Download/archive validation precedes removing an older installation. With neither input, existing latest behavior is unchanged. Gluetun supplies its selected source; no global major bump.
- **`setup_gs()`** — Install Ghostscript from source.
- **`setup_imagemagick()`** — Build ImageMagick 7 from source.
- **`setup_java()`** — Install Temurin JDK via Adoptium repo. Reads `JAVA_VERSION`.
- **`setup_mariadb()`** — Install/upgrade MariaDB (distro packages or official repo). Reads `MARIADB_VERSION`.
- **`setup_mariadb_db()`** — Provision database + user. Reads `MARIADB_DB_NAME`/`USER`/`PASS`. Exports DB vars.
- **`setup_meilisearch()`** — Install/upgrade MeiliSearch. Dump/restore migration for major upgrades.
- **`setup_mongodb()`** — Install/upgrade MongoDB. AVX check. Reads `MONGO_VERSION`.
- **`setup_mysql()`** — Install/upgrade MySQL (distro packages or official repo). Reads `MYSQL_VERSION`.
- **`setup_nodejs()`** — Install/upgrade configured Node.js via NodeSource, with safe cwd before all npm work and signing-key refresh before same-major apt metadata/upgrade. Retains noncritical key warning, module choices, npm/pnpm pins and safe heap limit.
- **`setup_php()`** — Install PHP + modules (Sury repo). Reads `PHP_VERSION`, `PHP_MODULE`, `PHP_APACHE`/`PHP_FPM`.
- **`setup_postgresql()`** — Install/upgrade PostgreSQL (distro packages or PGDG repo). Pre-upgrade dump/restore. Reads `PG_VERSION`, `PG_MODULES`.
- **`setup_postgresql_db()`** — Provision role + database. Reads `PG_DB_NAME`/`USER`/`PASS`. Exports DB vars.
- **`setup_ruby()`** — Install rbenv + ruby-build. Reads `RUBY_VERSION`, `RUBY_INSTALL_RAILS`.
- **`setup_rust()`** — Install rustup + toolchain + crates. Reads `RUST_TOOLCHAIN`, `RUST_CRATES`.
- **`setup_uv()`** — Select explicit UV_VERSION, then exact/compatible project required-version, then latest only without a requirement. `_uv_required_spec` shares TOML precedence/section/quote reading; `_uv_required_version` keeps its exact-only interface. Numeric AND ranges support ==/!=/</<=/>/>=/~= over completely paged, checked stable release enumeration. Unsupported65, no match250 and page/lookup errors never fall through to latest. USE_UVX/PYTHON_VERSION and same-version Python requests remain supported.
- **`setup_yq()`** — Install/update `mikefarah/yq`.
- **`setup_nltk()`** — Download NLTK data packages.
- **`setup_nonfree()`** — Enable Debian non-free repositories.
- **`setup_hwaccel()`** — Installs userspace for mapped Intel/AMD/NVIDIA devices, filtered by host `GPU_TYPE` and gated by `ENABLE_GPU`. Exports `HWACCEL_VENDORS` (space-separated available stacks) and `HWACCEL_VENDOR` (`nvidia`, `amd`, `intel`, or `none`, in preference order). NVIDIA requires libcuda and any mapped NVIDIA character node; a non-empty `INSTALL_NVIDIA_DRIVERS` supplies the install choice, otherwise the existing 60-second prompt defaults to yes on empty input, timeout or EOF. Its libraries are installed when the resolved choice is `yes`. Optional packages log directly to the active log, fall back to individual installs, and warn without aborting. Intel includes Vulkan/oneVPL and uses the compute-runtime release's pinned IGC tag, skipping OpenCL if unresolved. AMD ROCm requires `/dev/kfd`. Guest permission setup adds the service user (root by default) to render/video groups only; device attributes belong to host-side `fix_gpu_gids` via `pct set`.

### Utilities

- **`create_self_signed_cert()`** — Generate 2048-bit RSA cert with SANs.
- **`ensure_usr_local_bin_persist()`** — Persist `/usr/local/bin` in PATH across login/non-login shells.
- **`setup_local_ip_helper()`** — Install networkd-dispatcher hook for dynamic IP tracking.
- **`create_temp_dir()`** — `mktemp -d` with cleanup trap.

---

## `misc/error_handler.func` — Error traps

- **`catch_errors()`** — Enables `set -Ee -o pipefail`, installs ERR/EXIT/INT/TERM/HUP traps. Called by `bootstrap/lxc`, `build.func`, wrapper preamble.
- **`error_handler()`** — ERR-trap handler. Prints error info, writes container failure flag, may offer to destroy broken LXC. Reads exit code from `$1`/`$?`, command from `$2`/`$BASH_COMMAND`.
- **`on_exit()`** — Captures original status, removes its EXIT registration, performs due successful-update cleanup once in a noncritical subshell, then best-effort lock/pending handling and exits with the captured status. Failed updates retain pending state and skip cleanup; noncritical cleanup failure/exit cannot replace success. Existing failed-install collection/orphan handling remains.
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
