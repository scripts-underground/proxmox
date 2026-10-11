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
bash tests/codeberg-release.test.sh --bundle "$SCRATCH_CT" "$PROBE_URL"
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

## RomM/Codeberg safety and selection acceptance

The safety-gap runner is separate from the generic PVE harness above and never
imports its container cleanup. Run only as root in the positively identified,
private ark PVE VM, with Python 3.11+ (`tomllib`), Bash, jq, curl, tar,
zip/unzip, 7z, GNU coreutils and util-linux. Package prerequisites mean their
actual required binaries/capabilities, not executables named after packages.
Do not run in an installed application container
or on the desktop host.

Allocate a fresh owned `/var/tmp/su-corrections-*` session and a guest identity receipt
through the verified VM connection. The receipt records hostname, DMI UUID,
boot ID, exact allocated session and supervisor mount namespace; transfer
the historical helper separately and verify its Git blob. The canonical plan
and execution report under `~/Documents/ScriptsUnderground/plans/` describe
receipt preparation and captured full source/harness inventories (paths, modes,
Git blobs, SHA-256 and indexed-tree identity). Keep harness and source-under-test
in separate hash-matched roots. Independently pin the combined manifest's
SHA-256; never derive expectations from a convenient guest checkout/index.

```bash
timeout --foreground --kill-after=10s 1800 bash tests/run-safety-gap-tests.sh \
  --case-set all --source-role candidate --source-root "$CANDIDATE_SOURCE" \
  --source-manifest "$MANIFEST" --source-manifest-sha256 "$MANIFEST_SHA256" \
  --session "$SAFETY_SESSION" --guest-id "$SAFETY_GUEST_ID" \
  --baseline-tools "$BASELINE_TOOLS" --results "$SAFETY_SESSION/results.json"
```

The runner validates identity/source bytes before fixture writes. Every case is
a separate, private mount-namespace worker with fresh HOME/TMPDIR, target and
marker identities. Its synthetic bindings cover `/tmp`, `/opt`, `/etc`, `/var/lib`,
`/usr/local/bin`, the real version-cache location and zsh completion directory.
Only synthetic backing directories are used for symlink/mount/fault cases.
The selected manifest's actual live test is executed with deterministic transport,
and observed from outside its shell/traps. SIGTERM targets only the newly
created, barrier-identified worker process group. Workers/library come from the
verified harness; production helpers, RomM hook and live test come from the
selected source root. Baseline role executes the integrated production/live-test
bytes, preserving all 26 original detectors and the historical helper control.
`--case-set original` retains that schedule; `--case-set all` schedules 55 cases.

| # | Suite selector | Cases |
|---|---|---|
| 1 | `romm-repair` | R1–R5: real update-hook repair/preservation |
| 2 | `codeberg-deployment` | C1–C7: directory, symlink, bind-mount and interruption safety |
| 3 | `uv-selection` | U1–U12: effective-file precedence, lexical scope, quotes/comments, bare/exact overrides and targeted parse errors |
| 4 | `codeberg-pins` | P1–P7: numeric spellings, off-page pins, raw tags, transport status and metadata agreement |
| 5 | `live-cleanup` | L1–L2: actual consumer success/metadata-failure flow followed by owned cleanup |
| 6 | `release-transaction` | J1–J22: CLEAN/mounts/aliases, originals, leaf/marker/commit/restore faults, signals, serialization, capacity and conflict preservation |

Use `--suite <selector>` for an individual rerun and choose a new results path;
each invocation allocates fresh per-case roots. Logs, source hashes, witnesses,
legacy comparisons and detector controls are retained. Exit 0 means all safety
assertions pass; 1 means valid assertion failures; 2 means an ERROR/BLOCKED case
or unresolved harness control. Failures are investigation results, never
expected-failure annotations. `--capability-probe` separately proves the
documented rename/copy/mount/lock and foreground signal/finalizer primitives;
it is not a product-case pass or proof of a finished transaction. Its signal
controls include repeated group delivery during rollback. Original preservation,
deliberate-damage, namespace, signal and cleanup-allocation controls remain,
with journal/backup consistency and serialized mutation observations added.
The independent manifest-aware validator also checks all scheduled unique IDs,
fault/delivery/completion evidence and unchanged supervisor witnesses.

Originals/journals are intentionally retained outside disposable targets.
J12/J22 require genuine failed operations with safe retained recovery/conflicting
data; those operation errors are not converted to success. Disposable extraction
and live publication/restore temporary leak checks remain. Root inode/mount
identity is checked separately from regular leaf bytes/mode/link text. Keep
all failed/corrected snapshots, results and journals for review.

These are fixture safety/selection checks. Toy uv/executable artifacts are not
real dependency resolvers or full application installs. RomM repair probes do
not exercise gameplay; signal probes do not promise SIGKILL/power-loss rollback.
The original requirement-style override finding remains conditional; the
correction explicitly supports complete exact overrides. Cleanup
leaks alone do not establish the cause of a prior disk-capacity incident.

## Frozen-source review-gap investigation

The review harness tests unchanged candidate tree
`59264cc2846a5562f727d0b39af3762bd140b48e` with independent source and harness
inventories. Run only in the positively identified owned ark PVE guest. New
receipt-bound `/var/tmp/su-review-tests-*` sessions are private binds to the
approved separate test-storage disk; verify the bind, inode, disk origin and
monitored capacity before transfer or execution. All workers retain private
namespaces and synthetic bindings, including `/var/lib`. Production helpers
and the old live test come exclusively from the frozen source root.

```bash
bash tests/run-safety-gap-tests.sh --case-set corrections --source-role candidate \
  --source-root "$FROZEN_SOURCE" --source-manifest "$MANIFEST" \
  --source-manifest-sha256 "$MANIFEST_SHA256" --session "$CORRECTIONS_SESSION" \
  --guest-id "$CORRECTIONS_RECEIPT" --baseline-tools "$LEGACY_TOOLS" \
  --results "$CORRECTIONS_SESSION/results.json"

timeout --foreground --kill-after=10s 2700 bash tests/run-safety-gap-tests.sh \
  --case-set all --source-role candidate --source-root "$FROZEN_SOURCE" \
  --source-manifest "$MANIFEST" --source-manifest-sha256 "$MANIFEST_SHA256" \
  --session "$REVIEW_SESSION" --guest-id "$REVIEW_RECEIPT" \
  --baseline-tools "$LEGACY_TOOLS" --results "$REVIEW_SESSION/results.json"
```

| # | Case set | Schedule |
|---|---|---|
| 1 | `original` | Original 26 detectors |
| 2 | `corrections` | Existing 55, with strict per-invocation decision and rejection observations |
| 3 | `review` | K1–K15 only (`--suite review-gaps`) |
| 4 | `all` | Exactly 70 unique IDs; grouped variants retain separate evidence |

Successful calls must have COMMITTED decisions; completed rollback calls must
have ROLLED_BACK decisions and independently verified original consumers.
RECOVERY_REQUIRED is expected only for genuinely incomplete/conflicted calls,
not as an interchangeable successful outcome. Preflight rejection requires
initialized real-command observations showing no installed-entry or live-temp
mutation, in addition to equal before/after data. J7 witnesses its actual external
hardlink. Raw decision/operation files, statuses, hashes, events and consumer
snapshots remain referenced by each result.

The new external `review-validate-results.py` under the review plan's support
directory recomputes raw evidence in the guest. Complete mixed PASS/FAIL results
are valid investigation evidence; missing fault/barrier/identity observations
are ERROR, and unavailable capabilities are BLOCKED. K13/K14 are observer
sensitivity controls. Other K groups test the implementation, not manufactured
incidents. All prior assertions, controls, leaks and old reports remain intact.
These tests do not authorize production corrections, commits or publication.

## Review-correction execution and bounded selectors

The approved correction addendum uses a new uncommitted correction workspace
and separate captured candidate/harness inventories. New support, receipts,
validators and reports live under the plan's `review-corrections/`; the frozen
review source, harness, manifests and red evidence remain unchanged. The
invocation manifest independently records the expected case set/schedule.

For a correction group's exact bounded schedule:

```bash
bash tests/run-safety-gap-tests.sh --case-set all --only K1,K15 \
  --source-role candidate --source-root "$CANDIDATE_SOURCE" \
  --source-manifest "$MANIFEST" --source-manifest-sha256 "$MANIFEST_SHA256" \
  --session "$TARGETED_SESSION" --guest-id "$TARGETED_RECEIPT" \
  --baseline-tools "$LEGACY_TOOLS" --results "$TARGETED_SESSION/results.json"
python3 "$NEW_SUPPORT/validate-results.py" "$TARGETED_SESSION/results.json" \
  --manifest "$MANIFEST" --manifest-sha256 "$MANIFEST_SHA256" \
  --case-set all --expected-ids K1,K15
```

`--only` accepts nonempty, unique IDs from the declared case set and rejects
unknown/duplicate/empty IDs before execution. It cannot be combined with
`--suite` or capability mode. Every selected case keeps all of its named variants
and applicable controls; unrun groups are not reported passing. The independent
validator requires the externally captured schedule and selected variants.
K1 retains pipefail-on/off controls and adds truncated input and genuine
valid-output-then-nonzero producer variants. K15 retains all original verification
and rollback faults and adds genuine partial-reader-prefix failures.

Final acceptance retains all **70 unique IDs**, every required control and the
strict existing consumer/decision assertions, with no `--only` filter. Required
outcome is 70 PASS / 0 FAIL / 0 ERROR / 0 BLOCKED and independent validation exit
0. All commands run in the positively identified owned guests, with verified
disk-backed sessions, fresh boot/namespace receipts and monitored reservation
plus the unchanged 2 GiB free-space floor. A resource restart never authorizes
rewriting historical receipts or treating startup as product-function proof.

## RomM operational capacity checks

RomM recommends 2 CPUs/4 GiB RAM/32 GiB root allocation and checks its baked
8 GiB available-byte budget before dependency changes or update service stop.
The shared `check_available_storage_bytes` utility observes the actual requested
application/state/cache/HOME/tmp filesystems, resolves missing paths to existing
ancestors and checks each filesystem identity once. No capacity rejection may
create paths, stop services, discard data or be treated as an accepted deployment.
Controlled observer probes must cover below/exact budget, failed producers even
when bytes look valid, invalid output, missing ancestors and separate filesystem
budgets, including consumption through actual install/update hooks and a fresh
inlined bundle. Probes stay in owned private guests/namespaces; never fill shared
storage or change existing live bundles to trigger a low-space condition.

The measured real 5.3.0 install/5.3.1 update at 4 GiB RAM used one-second interval
sampling and actual service/HTTP/static-asset consumers. Its observed 4.54/4.33 GiB
filesystem high-water values do not prove between-sample maxima, unlimited ROM
library/retention capacity or a bare minimum root size. Sizing/source changes need
their own exact-candidate checks before final whole-suite acceptance.

## Phase-aware journal initialization and recovery

New schema-2 decisions distinguish verified preparation-only termination from
application-capable recovery using monotone `application_started`, sealed plan/
alias hashes and the complete plan count. Raw observer evidence must prove those
fields agree with actual application events and complete operation/original/input
records; a missing application record is not "nothing to undo." Preserve genuine
K2 missing/corrupt recovery specimens and K5 failed allocations before follow-up.
Retained `init-*` allocations are bookkeeping only and must not authorize live
mutation or block valid unrelated calls. A bootstrap publication followed by a
reported error must be observed as its actual published owner. J17 retains all
three cooperating call successes and serialized intervals; J21 requires status252,
zero installed/temp mutation and a verified preparation-only ROLLED_BACK decision
under fixture-limited ENOSPC, with old journals retained.

K3 includes already-restored bytes matching the former incoming value and native
mode-only edits to PREPARED/RESTORED originals. Recovery must preserve each
conflict and gate new deployment; the unedited retry stays supported. K4 covers
target-descendant store aliases, stacked aliases and target data reachable via
a proper descendant mount inside the store, with stable lock inode/contents and
canaries. A separate benign active owner proves an independent close-fds flock
contender cannot acquire the held lock; safe early rejection does not require
the former unsafe lock-publication barrier. Mount-origin/stack probes operate
only on fresh private fixtures and observe actual kernel/native identities.

The approved current-call `.read-*` workspace is separate from journals. Native
reader probes compare the canonical full-attribute file to independent xattr
values, cover genuine empty/link reads and malformed/failed/diagnostic producer
streams, require reused buffer identities under a filled private tmpfs with new
mktemp allocation blocked, and verify conflict retention/owned-only cleanup.
Public same-version calls must leave historical journal bytes/inodes/modes/
mtime/ctime unchanged; ordinary read-atime effects are not called journal writes.
Runtime prerequisite checks map the attr package to actual getfattr/setfattr
commands. New reader probes and failed evidence stay under the correction plan;
the final70-case gate remains required after the remaining corrections.

Phase E adds complete native xattr-set fingerprints and per-operation `attempts`
with distinct source/candidate/directory identities, observed partial results,
statuses/readiness and cleanup. Independent observers recompute metadata from
filesystem xattrs rather than trusting a production digest. K7 retains its
original publish/restore copy controls and includes zero/genuine fixture-tmpfs
partial copies and byte/mode/xattr/ACL/inode/hardlink edits. Failed-copy bytes and
native identities are retained before source finalization. Legitimate partials
must resolve without manual deletion; external conflicts must stay canonical
and gate retry. Native creation-observation windows preserve caught signals and
setgid/default ACL inheritance.

The approved K timing policy gives each declared subvariant120 seconds of work
and60 seconds for positively owned-group finalization. Its enclosing K group
gets120 × captured variant count +60 seconds; ordinary workers keep120 seconds
and final acceptance retains2700 seconds overall. Each variant has its own
session/process group and private namespace/context. The pinned invocation
captures the independent ordered variant list and computed budgets. Enclosing
INT/TERM is forwarded only to the verified active child group, followed by
bounded quiescence; no further child starts. Timeout/identity/setup/teardown
failure stays ERROR. Independent validation checks all nested groups/contexts/
commands/statuses and every original contract. Prior timed-out evidence is not
recertified; shared hooks/CI/configuration are unaffected.

Phase F verifies genuine CLEAN rollback with access/default ACLs, binary user
attributes and escaped native names; inherited extra attributes must be removed
only from a proven recreated-directory baseline. Native tar originals are
nonrecursive, their restored replicas empty, and timestamp references survive
observation without reading the zero-byte reference data. Independent directory
consumer timestamps/ACL/xattrs and artifact hashes prove the final outcome.
K10 additionally exercises a deeper retained intermediate alias with an eligible
obsolete sibling, proving skeleton protection is not a blanket subtree exemption.

Phase G preserves LF controls and consumes valid CRLF pyproject/uv.toml exact
pins through the real fixture binary/cache/download URL. Codeberg metadata
agreement is checked on raw JSON strings before shell trimming; K12 retains its
original numeric/raw controls and adds non-ASCII/slash spelling plus whitespace/
control suffix rejection. Invalid metadata must leave markers unchanged and
clear stale selection; no legitimate Git-ref newline claim is made.

Legacy compatibility probes seed genuine journals using the immutable frozen
schema1 implementation before loading the candidate. Structurally valid completed
history stays read-only, valid PREPARING/no-application progress may terminate
with explicit preparation-only proof, and unsafe active/missing/unknown records
must refuse without changing canonical data or deleting retained originals.
No handwritten state is substituted for those seed operations. The exact final
source still requires one fresh complete70-case acceptance and real regressions.
