# Tests

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
