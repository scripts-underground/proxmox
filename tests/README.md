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
