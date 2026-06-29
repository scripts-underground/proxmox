# Changelog

## 2026-06-28

### Breaking

The framework was converted from the upstream Proxmox VED layout to the fork's own infrastructure. All telemetry was removed (`misc/api.func` deleted — 1475 lines), `description()` was renamed to `complete_install()` and expanded to own the `post_install_script` hook, the bootstrap shim was slimmed to 14 lines, and dead variables (`METHOD=`, `RANDOM_UUID`/`EXECUTION_ID` exports) were stripped. The Diagnostics menu option was removed alongside all `post_*_to_api` calls. Framework files now pass `bash -n`.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [<HEAD>]

### Fix

A parse-breaking orphan curl tail in `error_handler.func` (leftover from `_send_abort_telemetry` deletion) was removed. A live call to the deleted `post_to_api` function in `build.func`'s `create_lxc_container` was also removed. All six `.func` files now pass `bash -n` cleanly.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [<HEAD>]
