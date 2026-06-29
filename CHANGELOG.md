# Changelog

## 2026-06-28

### Breaking

The framework was converted from the upstream Proxmox VED layout to the fork's own infrastructure. All telemetry was removed (`misc/api.func` deleted — 1475 lines), `description()` was renamed to `complete_install()` and expanded to own the `post_install_script` hook, the bootstrap shim was slimmed to 14 lines, and dead variables (`METHOD=`, `RANDOM_UUID`/`EXECUTION_ID` exports) were stripped. The Diagnostics menu option was removed alongside all `post_*_to_api` calls. Framework files now pass `bash -n`.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [483964d]

### Feature

Every script in the project was ported from the upstream JSON-pair metadata format to the fork's single-file format with YAML frontmatter. The script catalog covers LXC, Addon, PVE, and VM types — 107 files across `scripts/` and their corresponding `_<type>/` page stubs. Host-bound addon scripts that should not have user-facing script pages were removed from the catalog (add-iptag, add-tailscale-lxc, code-server, netdata).

- Port scripts and content pages to fork format [<HEAD>]

### Fix

A parse-breaking orphan curl tail in `error_handler.func` (leftover from `_send_abort_telemetry` deletion) was removed. A live call to the deleted `post_to_api` function in `build.func`'s `create_lxc_container` was also removed. All six `.func` files now pass `bash -n` cleanly.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [483964d]
