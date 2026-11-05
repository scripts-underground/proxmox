---
slug: kosmozoo
title: Kosmozoo
tags: [comfyui, review, curation]
logo: /assets/logos/kosmozoo.webp
by: alexindigo
repo: https://github.com/alexindigo/kosmozoo
site: https://github.com/alexindigo/kosmozoo
port: 80
cpu: 2
ram: 1024
disk: 4
maintainer: alexindigo
---

Kosmozoo is an image review and curation engine for ComfyUI output and local folder sources. This installer deploys the published **GNU/Linux x86_64** executable, including its web UI, native SQLite and bundled plugins, into an unprivileged Debian 13 container. Fresh `kosmozoo serve` services use a dedicated static **non-root kosmozoo account** on **HTTP port 80**, with only `CAP_NET_BIND_SERVICE` supplied by systemd. Code remains root-controlled; no executable file capabilities are installed. Deno, Python, Node, Docker and a browser are not application-runtime requirements. The binary requires glibc >=2.27; musl/Alpine is unsupported.

## Notes

- Starts with **no sources**. Add a source in the UI, or set `KOZMOZOO_HOSTS='studio=comfyui.lan:8188,local=folder:/sources/images'` when invoking the installer. Bare HTTP hosts are saved with explicit `:80`; explicit decimal ports must be 1..65535. Spaces around pairs are trimmed; duplicate names, controls and empty entries are refused. The native spelling is `KOZMOZOO_*`.
- Public install inputs `KOZMOZOO_STATE`, `KOZMOZOO_CACHE` and `KOZMOZOO_HOSTS` cross the container boundary through overrideable `var_lxc_kosmozoo_state`, `var_lxc_kosmozoo_cache` and `var_lxc_kosmozoo_hosts`. Paths are **inside the LXC**. State and cache paths must be absolute/canonical, separate from managed code, plugins and temporary storage. Literal spaces and shell punctuation are data, not commands.
- Runtime configuration is `/etc/kosmozoo/env`, a **systemd EnvironmentFile**, not a shell script. Normal updates preserve this file, the unit and administrator drop-ins. Restart `kosmozoo` after changing runtime configuration.
- The installer/updater's systemd property queries use the standard system D-Bus. Fresh installs include Debian's `dbus` OS package and verify its normal socket and manager access. This is installer support, not an engine dependency. An updater with unavailable bus access stops before download/service stop and reports how to check `dbus.socket`/`dbus.service`; it never installs or reconfigures the bus automatically.
- `KOZMOZOO_HOSTS` is a seed **whenever the native collection table is empty at boot**, including after all sources have been deleted. Existing nonempty collections win. Keep `KOZMOZOO_HOSTS=""` to disable re-seeding; the updater never clears a configured seed.
- Managed code: `/opt/kosmozoo/kosmozoo`. Persistent state: `/data/state` (SQLite database, WAL/SHM, settings, backups, lease and quarantine files); cache: `/data/cache`; trusted plugin drop-ins: `/data/plugins`; disk-backed native temporary storage: `/data/tmp`; application `HOME`: `/data`. Back up the **whole state directory**, including migration backups and WAL/SHM. State must use a real local filesystem with SQLite WAL/locking support, never NFS/SMB. Votes, independent favorites/bookmarks and notes are SQLite records; feedback exports are generated through HTTP.
- New managed runtime directories are owned by the resolved service UID/GID. Existing state/cache/HOME/TMPDIR must already be service-owned and readable/writable/traversable by the actual service credentials; plugin and media paths need read/traverse access. Existing paths, accounts and metadata are validated, never repaired. `TMPDIR` must be writable, disk-backed and allow executable mappings: bundled SQLite is extracted there at startup. Root-private administrative staging and root0600 EnvironmentFiles remain private; runtime-private instance metadata instead belongs to the service UID with mode0600.
- Source media and mounts remain operator-managed. The installer does not mount, remount or recursively change ownership of existing data. Folder sources need read/traverse access; explicit deletion permanently unlinks files when permissions allow. Cache is **unbounded** and grows with ingested image bytes; plan storage for your collection and update staging. The 2 CPU / 1024 MiB / 4 GiB defaults are not a capacity guarantee for arbitrary library size.
- Folder seeds such as `local=folder:/sources/images` must name an existing directory readable/traversable **by the actual runtime user inside the LXC before first start**. Mount/provide it first, or install with the default empty seed and add the source after mounting. The installer validates the full seed before application installation, but never creates a missing source directory or changes its ownership.
- The installer selects a **published release**, not the current application checkout. The published v0.3.0 includes bare-host normalization and all-folder seed admission; this installer retains its overflow-safe port validation and stricter duplicate/control refusals.
- The HTTP service has **no authentication** and is intended for trusted LAN use. Plugins are trusted local code. Optional external detection/critic services are separate deployments; no GPU, models or inference service is installed.
- An access-controlled reverse proxy must preserve the original **Host** header and **Origin**. Browser mutations require matching origins; rewriting Host can break saving judgments/settings. Origin-less API clients are accepted. No trust-proxy bypass is configured.

## Updates and recovery

The updater supports this native layout only. It selects a stable published release once, verifies the executable against both its API-associated SHA256 and one unambiguous expected-filename record in **SHA256SUMS from that same release**, and downloads and validates the candidate while the old engine remains running. An explicit initial `var_appversion` selects only the first install; it does not become a permanent update pin. Updates use the current explicit version request or latest stable, not a permanent v0.3.0/hash pin.

Updates preserve existing units, EnvironmentFiles, drop-ins, data ownership and explicit root-run services. They resolve the effective static User/Group/supplementary groups and use that identity for access, probes and instance/process checks. Dynamic or unresolved identities and unsupported private-user/alternate-root contexts fail before app changes. Fresh non-root defaults do **not** migrate existing root-owned data or units; no recursive chown, stable-lock deletion or automatic identity migration is performed.

Install and update share the framework's per-app maintenance owner, including direct cold-hook calls. A competing invocation returns **status 75** before layout/version-floor admission, release selection, service stop or publication. Retry after the current owner finishes; never delete a maintenance lock file or force a takeover. A hook called by the normal updater borrows that updater's validated ownership through recovery and outer cleanup. A busy invocation does not clear another invocation's pending update.

Activation drains the service gracefully (without force-killing writers), atomically replaces the executable, and checks the actual unit's matching `/api/runtime` readiness, version, binding and private instance before advancing `/root/.kosmozoo`. Operator bind/port overrides are respected. Native runtime protocol version 1 and per-start instance nonces are distinct from the release version.

A pre-start failure preserves old code/state/marker; the updater restarts old code only when this invocation stopped an engine that was running on entry. If the candidate may have opened state, failure stops and disables normal boot of the service **before restoring older code/marker**, retaining all state and recovery evidence. If stopping or disabling fails, the candidate remains in place. Inspect the diagnostic recovery directory and `/opt/kosmozoo/activation-attempt.json`; repair with the same or a newer release. A retained attempt prevents an older explicit pin, even when an older marker was restored. Do not manually start restored old code against potentially upgraded state. No database rollback or Python-era migration is performed. Cleanup failure after committed healthy activation reports pending/nonzero while leaving the new service/code/marker in place.

Already accepted jobs run remotely on ComfyUI while Kosmozoo restarts or updates; the engine can observe their queue/history and ingest completed output afterward. This does not promise a durable local submission queue, unchanged progress/nonce/epoch, recovery of unsent browser work, cancellation, retry or wait-for-idle policy.

## Links

- [GitHub](https://github.com/alexindigo/kosmozoo)
