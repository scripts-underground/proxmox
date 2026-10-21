# Tests

## Focused maintenance contracts

These plain Bash tests run inside an isolated Linux VM with an existing writable
disk-backed `TMPDIR`; the guest's `/tmp`/tmpfs is not a fixture destination.
Native bind-fixture modes require root and a private mount namespace. Set TMPDIR
inside the admitted project workspace before launching a test. They do not call
the legacy CT-destroying harness described below.

| # | Test | Actual outcome and modeled boundary |
|---|---|---|
| 1 | `maintenance-silent.test.sh` | Actual core/error helpers: same-shell effects, exact handled/fatal statuses, retry, quiet log bytes, pipeline semantics, options and ERR restoration (including command mutation); spinner UI only is stubbed |
| 2 | `maintenance-cleanup.test.sh` | Default filesystem-literal model supports safe RED; `--native` uses unmodified helpers with private disk-backed root/cache/state binds. Actual cache bytes/pending/exit outcomes; package/language executables are modeled, not real package removal |
| 3 | `maintenance-temp-root.test.sh` | Default literal-path instrumentation supports safe RED; `--native` executes unmodified temp/cache/bundle/API helpers. Curl/pct and final addon-destination writing are modeled; fetched/delivered bytes and owned-stage cleanup are actual files |
| 4 | `maintenance-build-temp.test.sh` | Actual normal/retry preparation fragments and bundle assembler, executed receiver environment/path/mode and failed-preparation boundary; pct/OS hooks are modeled. `--baseline` reads immutable5914963 history and instruments its old paths for the intended negative control |
| 5 | `maintenance-bundle-bootstrap.test.sh` | Actual install bootstrap and error/cleanup consumer against modeled deployed-baseline network responses; mapped filesystem literals. Verifies already inlined handlers are not refetched/replaced |
| 6 | `maintenance-consumers.test.sh` | Actual Aria2 update and generated MQTTX uninstall: failed required commands retain status/pending or installed markers and never claim success in either STD mode. Filesystem literals and external executables are modeled |
| 7 | `maintenance-receiving-context.test.sh` | Actual install/update/uninstall preludes: missing/recreated shared sticky receiving directories before first library write, existing metadata, default, invalid paths, receiver-only symlink validation and mkdir failure. Tiny framework libraries and pct are models |
| 8 | `maintenance-retry-preservation.test.sh` | Actual recovery menu and repair branch under DEV_MODE_KEEP=false: failed receiver/bundle/alias preparation preserves exact status and never re-enters destructive prompts or executes stale bytes. Recording pct model; no CT mutation |
| 9 | `maintenance-bundle-writer.test.sh` | Actual writer in conditional and plain callers: allocation/read/missing-cache/context/hook/write failures plus partial-push/mode/rename faults, owned sender/receiver stage removal, previous command bytes/mode preservation and no partial publication; real ENOSPC sink, modeled pct |
| 10 | `maintenance-uninstall.test.sh` | Actual Dockge hook/addon bundle and LXC uninstall owner, failed commands/returns in both STD modes, preserved data/commands/marker, actual ERR log/status and owned spinner stop through a guest PTY. Docker and prerequisite APIs are modeled; no host UI claim |
| 11 | `maintenance-receiver-portability.test.sh` | Extracted actual Alpine BusyBox via ALPINE_BUSYBOX, portable path/symlink behavior, real nonroot child tempfile creation in a private disk-backed mount fixture; existing agent workspace stays private |
| 12 | `maintenance-addon-writer.test.sh` | Actual conditional addon producer/publication, cat/missing/context/ENOSPC/mode/link/rename failure status, unchanged previous valid bytes/mode, owned-stage removal and successful executable output |
| 13 | `maintenance-nodejs.test.sh` | Actual setup/key/cache helper files and order, deleted cwd, same-major refresh, warning and existing pins in both STD modes. Package/network/crypto commands modeled in private disk mounts |
| 14 | `maintenance-uv-range.test.sh` | Actual shared reader/setup/cache/install consumer: exact/override/AND/compatible bounds, exclusions, failed/unsupported/no-match outcomes. Downloaded uv artifacts and external responses are modeled; extraction/executable bytes are real |
| 15 | `maintenance-release-metadata.test.sh` | Actual deploy/older selection/public getter/IGC consumer: checked producer/JSON, two independent repositories, selected older metadata across the optional subshell, stale clearing, requested-asset refusal and token recovery reaching archive download. Responses/artifacts modeled |
| 16 | `maintenance-prefix-arch.test.sh` | Actual getter/checker/deployer/source bytes, default/pin/force/raw-tag behavior, optional stable prefix and explicit architecture aliases. Responses/artifacts and detection commands modeled |
| 17 | `maintenance-release-boundaries.test.sh` | Actual checker/source deployer, empty/prerelease-only fallback, missing pins, first older asset within15 releases, refusal of ancient/partial/malformed selection, real owned-spinner/log/status outcomes through a PTY. HTTP/Git producers modeled |
| 18 | `maintenance-gpg-key.test.sh` | Real GPG invalid/truncated input and native nonroot key reader, old bytes/mode/owner retained across failures, private stage cleanup and apt-readable fresh key. Requires a valid public key in GPG_FIXTURE; curl and write/mode/owner/rename faults modeled |
| 19 | `maintenance-service-uninstall.test.sh` | Actual init helper, Actual Budget exporter/AdGuard/phpMyAdmin/Netvisor hooks and generated addon/LXC owners in both STD modes. Absent/stopped/disabled reruns, query/control failure statuses, retained real files/commands/markers, all22 caller adoption and unchanged existing helpers/other8 hooks. systemd257/OpenRC0.62 external commands are source-characterized models |
| 20 | `maintenance-service-systemd.test.sh` | Native installed systemd and actual AdGuard hook: absent/stopped/disabled outcomes, refused stop, denied disable and unavailable-manager query. Requires explicit L2_NATIVE_FIXTURES=owned-maintenance-vm; installs only uniquely named owned unit fixtures and verifies their removal. No full app install and no native OpenRC claim |
| 21 | `maintenance-keep.test.sh` | Real filesystem/source/archive replacement: nested/hidden/missing keeps, default/ancestor collisions, links, native nested bind mounts including spaces, bad paths before effects, root/source metadata, preparation/move/copy/restore failures and retry; ten real provider paths with modeled network producers. Existing GitLab metadata literal is disk-mapped for its fixture |
| 22 | `maintenance-app-preservation.test.sh` | Actual CLIProxyAPI/Sure/PrivateBin/ByteStash hooks, release helper and pending-update owner in both STD modes; real config/uploads/current+legacy data, identity/metadata, copy/build failure and forced retry, missing critical config, existing unit settings and fresh ByteStash override/metadata checks. Downloads/builds/runtime/service commands modeled; implicit /opt defaults isolated by private bind fixtures |
| 23 | `maintenance-service-edges.test.sh` | Actual helper, source-characterized boundary models: retained failed/running tombstones, bad/empty fields versus malformed/failed queries, exact control errors, caller output named state, all OpenRC runlevels and reserved local namespace |
| 24 | `maintenance-service-edge-native.test.sh` | Native installed systemd removed-file active/failed and broken-setting states, actual stop outcome and caller output in both STD modes; explicitly authorized uniquely owned fixtures removed afterward |
| 25 | `maintenance-app-compat.test.sh` | Actual OneDev/Apprise/Pelican/Sonarr/Wiki.js/Gluetun hooks, release/Go helpers and update owner. Native file/config and PHP Dotenv parsing, actual first/repeated CSS HTTP consumer, old/new units, architecture/line selection, SQLite conditional behavior and selected-source Go/pin outcomes. Downloaded build artifacts/Go executables, compilers, DB/runtime provisioning and services are labeled models; requires admitted upstream CSS/supervisor references and native PHP/Dotenv prerequisites |
| 26 | `maintenance-replacement-review.test.sh` | Native GNU/Alpine merge-type and destination-symlink refusal; planned-partial rollback versus unrelated root/nested writers; source hardlink/independent-directory metadata; checked partial-link/full-copy failure and actual loop-backed ext4 cross-device fallback; lossless array and invalid-path controls; populated-tree bytes and bounded operation counts. Requires root/private mount namespace and `ALPINE_BUSYBOX`; large50k proof uses `REPLACEMENT_LARGE_SIZE=50000`, freshly admitted `REPLACEMENT_TASK_WORKSPACE` and explicit `REPLACEMENT_TASK_BUDGET_BYTES` (account for any task data outside that workspace before supplying it), with every fixture under disk-backed TMPDIR and the existing8GiB root reserve retained |
| 27 | `maintenance-merge-inplace.test.sh` | Native populated old-only directory/file/hardlink identity and actual copy-byte accounting, independent SUCCESS writer in merge/dot-merge, conflicting restore aside retention/no nesting, and newly appearing native bind mounts inside stage/aside before cleanup |
| 28 | `maintenance-go-minimum.test.sh` | Actual source minimum/toolchain parsing, installed-satisfying/no-downgrade, checked minor-patch/legacy tag selection, explicit pin priority, duplicate/malformed/failed-producer/no-match/download negatives and installed executable consumer; tiny downloaded artifact executables are explicitly models |
| 29 | `maintenance-runtime-hooks.test.sh` | Cold Radicale/Discourse/ThingsBoard/AliasVault fresh/update/failure/retry hooks, native TOML/INI parsing, both STD modes and actual persistent files/units/pending owner. Compilers, runtime/database provisioning and service controls are explicit models |
| 30 | `maintenance-build-hooks.test.sh` | Cold Tracearr/Twenty/Kima/Paperclip/Paperless fresh/update/failure/retry paths. Native Node shared/emails/logo and migration-environment consumers; native Dotenv/JSON and actual v2/v3 Paperless filters; exact pnpm diagnosis, preservation, restart overrides and before-effects refusals. Neural artifacts/checksums, compilers, database and services are explicitly modeled |
| 31 | `maintenance-node24-vite.test.sh` | Native Node24 checks every declared engine range in the supplied AliasVault lockfile using npm's semver implementation, installs the resolved Vite with strict engines and observes generated HTML/JS from a bounded compiler fixture. Requires admitted `RUNTIME_NODE`, `RUNTIME_NPM` and immutable `RUNTIME_EXTRA_REFERENCES`; not the whole app build |
| 32 | `maintenance-paperless-format-source.test.sh` | Actual immutable v2 function and v3 ConsumerFilter/watchfiles demonstrate wildcard-directory and absolute-root counterexamples. Native Dotenv parses JSON and quoted secrets; these expected capability differences support checked refusal, not an approximate conversion |
| 33 | `maintenance-webtrees.test.sh` | Actual fresh/update/same-version cold hooks; native Caddy validation before publication/service control and private-network HTTP403 protected files versus200 exact immutable upstream CSS/JS. Custom Caddy bytes, validation failure, data and failed-copy boundaries are observed; PHP/DB/service/network commands are modeled |
| 34 | `maintenance-zigbee2mqtt.test.sh` | Actual cold update, native tar/zstd decompression and archived settings/database bytes in both STD modes; repeated same-version unique archives, producer/sink failure status and partial cleanup; source/build/copy failure data preservation. Network/build/service commands modeled |
| 35 | `maintenance-immich.test.sh` | Cold fresh/update/source-pin/library/CPU/same-version/missing-record/failure controls, native selected-source country-name reader and live CLI publication checks; disk-backed cross-device global scratch proves app-disk projection without full-copy fallback; each pnpm/tool/ML/publication failure checks exact current-stage cleanup, prior unknown-stage retention, source inputs and status/retry/pending truth. All mutable roots are validated/mapped before execution with VM-global pre/post boundaries. CLI artifacts, image/app compilers, ML, DB/service and other downloads are explicitly modeled |
| 36 | `maintenance-retry-callers.test.sh` | Native execution of actual Frigate wheel and all eight Immich Python/ML loop fragments in quiet/verbose modes; all three attempts, reachable third-attempt recovery, exact exhaustion status and no false continuation/success. Dependency commands are models |

The build-hook Paperclip controls include actual fresh install with inherited
INSTALL_LOG and higher-priority _HOST_LOGFILE in both STD modes. Only an exact
structured stale-lock failure unlocks; other failures remain fatal. The OneDev
compatibility controls retain unknown legacy extraction paths and exercise failed
version selection followed by a clean archive retry with no old-only jar mixing.
Webtrees native controls cover optional root matcher, trailing slash and quoted
equivalent static forms, plus checked unrelated/ambiguous-root refusal. Immich's
private app stage and its call-scoped publication projection must share the live
install disk. A loop-backed global scratch filesystem stays separate. Exactly the
current owned app stage is cleaned on checked build/publication failure; original
failure status wins if cleanup also reports failure, and cleanup failure cannot
become overall success. The existing venv's in-place ML dependency synchronization
is not an atomic rollback contract.

Forgejo's native acceptance requires explicitly owned fresh CTs and actual HTTP
onboarding/port80, SSH clone+push/independent-consumer and real custom-home/key/
data/port update outcomes for Debian and Alpine independently. These are separate
native fixtures with explicit admission/ownership; source-only tests cannot mark
a resource-blocked variant verified. Every nested workload, daemon and Git/SSH
client uses a disk-backed project TMPDIR writable by its actual operating user.

Example commands **inside the admitted VM**, with TMPDIR already set:

```bash
timeout --signal=TERM --kill-after=5s 120s bash tests/maintenance-silent.test.sh
timeout --signal=TERM --kill-after=5s 120s bash tests/maintenance-cleanup.test.sh --native
timeout --signal=TERM --kill-after=5s 120s bash tests/maintenance-temp-root.test.sh --native
timeout --signal=TERM --kill-after=5s 120s bash tests/maintenance-build-temp.test.sh
timeout --signal=TERM --kill-after=5s 120s bash tests/maintenance-bundle-bootstrap.test.sh
```

`update-pending.test.sh` binds only the pending directory to its disk fixture,
leaving a workspace elsewhere under `/var/lib/scripts-underground` visible.
`container-install-failure.test.sh` preserves both inherited-creator/default and
explicit receiving `var_lxc_tmpdir` assertions; its unset-creator allocation case
labels and instruments the legacy default rather than writing into guest RAM.
These fixtures establish helper/lifecycle outcomes, not full application installs,
real package maintenance or postponed hardware behavior. Every native command
status must be captured before reporting a result; an infrastructure/fixture
failure is not proof of the target regression.
The cleanup test includes no-new-release success explicitly: no deployment occurs,
but successful EXIT cleanup still runs once, including the package manager's
autoremove behavior. This is the approved success contract, not a failed update.
Unrelated `tmp*`/`tempfile*` files in custom and system-like temporary roots and
shared temporary contents must survive cleanup; package/language cache assertions
remain unchanged. New receiving intermediate components use0755 and only the
selected leaf uses01777; tests observe nonroot temp creation, inability to squat a
removed leaf and owner recreation. Existing selected paths retain
metadata and must already support the intended child users. This receiving
contract does not change private agent workspaces or SSH TMPDIR permissions.

`uv-project-version.test.sh` is a live runtime test: it additionally checks a closed
uv range and runs the real uv/project Python consumer. `github-force-deploy.test.sh`
uses live release metadata/assets. Run these only in the assigned VM's disk-backed
namespace with writable runtime/profile/cache/completion paths isolated. Network
or rate-limit failure is a recorded live-proof blocker, not a passing mocked test.

End-to-end test scripts for community scripts against the PVE VM. Each
script installs a community LXC script on the PVE testbed, validates the
result, and reports pass/fail.

## Quick start

```bash
# Run the CWA test
./tests/calibre-web-automated.test.sh
```

Requires:
- PVE VM reachable at `192.168.122.50` (override with `PVE_HOST`)
- SSH key deployed on the PVE VM
- Outbound TCP working on PVE

## How tests work

### Generic checks (every test)

Every test script runs these phases:

| Phase | Check |
|---|---|
| Preflight | PVE reachable, outbound TCP works |
| Cleanup | Destroy containers 100 and 101 |
| Install | Run the community script on PVE, extract CTID |
| Services | All expected systemd services active |
| Users | All required user accounts exist |
| Paths | All required directories present |
| Web UI | App responds on its configured port |
| Logs | No forbidden patterns in service logs |

Each phase uses helpers from `tests/lib/test-common.sh`. When a second
test script is written, these will extract into a shared harness.

### App-specific checks

Test scripts can add app-specific phases after the generic checks. The
CWA test adds a book upload phase (Phase 9) that authenticates with
CSRF, uploads a test EPUB, waits for ingest, and verifies the book
count increases.

## Codeberg release helpers

Run these inside a disposable Linux guest with `bash`, `jq`, `curl`, `zip`,
and `unzip` installed:

```bash
bash tests/codeberg-release.test.sh
bash tests/codeberg-release.test.sh --live
```

The deterministic suite covers release selection, pins, bounded API requests,
malformed responses, interrupted downloads, staging cleanup, and preserving an
existing installation when copying or publishing a replacement fails. It does
not invoke the PVE harness or destroy containers.

The live mode fetches and redeploys all four Codeberg consumers' actual releases
in temporary directories using the framework's verbose and quiet modes. It checks
version markers, configuration preservation, source files, and executable
versions. These are release-helper checks, not full application/service installs.

To verify the actual persistent-bundle path, serve the candidate checkout over
HTTP and run this on the disposable PVE guest, supplying a test container ID:

```bash
bash tests/codeberg-release.test.sh --bundle 103 http://192.168.122.50:8001
```

It uses `build_bundle()` to inline the candidate framework and a probe hook,
then deploys and runs Readeck from the resulting update bundle inside that CT.

## RomM player-serving probe

In a fresh disposable guest, install the prerequisites and run:

```bash
bash tests/romm-player-serving.test.sh --setup
bash tests/romm-player-serving.test.sh
```

This deploys actual EmulatorJS `.7z`, Ruffle ZIP and uv TAR releases using the
GitHub helper. It runs the Angie configuration extracted from `romm.sh` on port
8080, with fixture SPA HTML, and checks isolation headers, ordinary SPA routes,
and byte-for-byte HTTP delivery of the emulator loader and DOS core. It does
not install the RomM backend or prove in-browser gameplay. The guest must not
already have `/opt/romm/frontend/dist/index.html`.

## uv project-version helper

Run as root inside a disposable VM/container with `curl` and `jq` available:

```bash
bash tests/uv-project-version.test.sh
```

It uses real uv releases to check exact pins in `pyproject.toml`/`uv.toml`,
explicit override precedence, selecting an older release, and latest fallback.
It also verifies that an already-installed uv still installs a newly requested
Python interpreter, that `uv sync` selects a project-compatible Python despite
a different setup request, and that helper calls preserve the caller's exit trap.

## Same-version GitHub asset repair

```bash
bash tests/github-force-deploy.test.sh
```

Run inside a disposable guest. It deploys a real release, damages only its
temporary test payload, verifies normal same-version idempotence, and verifies
that `FORCE_DEPLOY=1` repairs the payload while retaining the correct marker.

## Installed RomM verification

```bash
bash tests/romm-live-verification.test.sh
```

Run inside a disposable installed RomM container. It checks the actual built
player assets over HTTP, isolation headers, and active/enabled services. It also
checks the cron process's configured schedules in Redis and sends isolated
probe jobs to both ordinary and scan queues, verifying the returned results.

## Configuration

Each test script has a config block at the top:

```bash
SCRIPT_NAME="app-name"
EXPECTED_SERVICES=(svc1 svc2)
REQUIRED_USERS=(user1)
REQUIRED_PATHS=(/path1 /path2)
WEB_PORT=80
FORBIDDEN_LOG_ERRORS=("pattern1" "pattern2")
```

Per-script details:

| Script | What it validates | App-specific phase |
|---|---|---|
| `calibre-web-automated.test.sh` | CWA LXC install | Book upload via CSRF, ingest pipeline, `abc` user, Docker paths |

## Writing a new test

1. Copy `calibre-web-automated.test.sh` as a template
2. Update the config block with the new app's services, users, paths
3. Add any app-specific phases after the generic checks
4. Place test assets in `tests/assets/`

## Shared library

`tests/lib/test-common.sh` — sourced by every test script. Provides:

- `pass()` / `fail()` / `warn()` — colored output
- `pve_exec()` / `pve_pct()` — SSH wrappers
- `preflight_checks()` — connectivity + outbound TCP
- `cleanup_containers()` — destroy CT 100, 101
- `check_service()` / `check_user()` / `check_path()` — single checks
- `check_no_log_errors()` — grep for forbidden patterns in journalctl

## Test assets

`tests/assets/` holds files needed by tests:

| File | Description |
|---|---|
| `the-raven-noimages.epub` | The Raven (Poe, 1845), public domain. 52 KB. Project Gutenberg #17192. Used by the CWA book upload phase. |

## PVE VM

The test scripts target a PVE VM at `192.168.122.50`. The VM should:
- Have the scripts-underground repo cloned at `/opt/scripts-underground`
- Have the `debian-13` LXC template available
- Have a working bridge (`vmbr0`) and outbound internet
- Be clean (no leftover containers from previous runs)

The `cleanup_containers` phase destroys CT 100 and 101 before each run.
If your VM has important data at those CT IDs, override the CTIDs or
skip the cleanup phase.
