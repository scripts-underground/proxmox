# Changelog

## 2026-06-28

### Breaking

The framework was converted from the upstream Proxmox VED layout to the fork's own infrastructure. All telemetry was removed (`misc/api.func` deleted — 1475 lines), `description()` was renamed to `complete_install()` and expanded to own the `post_install_script` hook, the bootstrap shim was slimmed to 14 lines, and dead variables (`METHOD=`, `RANDOM_UUID`/`EXECUTION_ID` exports) were stripped. The Diagnostics menu option was removed alongside all `post_*_to_api` calls. Framework files now pass `bash -n`.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [483964d]

### Feature

Every script in the project was ported from the upstream JSON-pair metadata format to the fork's single-file format with YAML frontmatter. The script catalog covers LXC, Addon, PVE, and VM types — 107 files across `scripts/` and their corresponding `_<type>/` page stubs. Host-bound addon scripts that should not have user-facing script pages were removed from the catalog (add-iptag, add-tailscale-lxc, code-server, netdata).

- Port scripts and content pages to fork format [64f4e53]

Syntax highlighting was replaced with a custom AST-driven rendering pipeline. The Go-based tool (`tools/ast/main.go`) uses mvdan/sh to parse bash scripts into typed token spans (16 token kinds) and emits schema-v2 JSON under `_ast/`. The Jekyll layout renders source code using these tokens directly, eliminating highlight.js (1253 lines of vendored JS and CSS removed). The tool also classifies scripts for safety (host-bound logic, external sources, eval, tool flags) — data consumed by the Jekyll plugin for per-page safety warnings.

- Replace highlight.js with AST-driven token rendering [<HEAD>]

### Fix

A parse-breaking orphan curl tail in `error_handler.func` (leftover from `_send_abort_telemetry` deletion) was removed. A live call to the deleted `post_to_api` function in `build.func`'s `create_lxc_container` was also removed. All six `.func` files now pass `bash -n` cleanly.

- Fork-shape framework files: remove telemetry, rename description to complete_install, slim bootstrap shim [483964d]
