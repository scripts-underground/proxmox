#!/usr/bin/env bash
# Guarded primitive prototype and transaction worker; never run on the host.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"

capability_result() {
  python3 - "$1" "$2" << 'PY'
import json
import os
import pathlib
import sys
path = pathlib.Path(os.environ['SG_CASE']) / 'capability-results.json'
records = json.loads(path.read_text()) if path.exists() else []
records.append({'id': sys.argv[1], 'status': sys.argv[2]})
path.write_text(json.dumps(records, indent=2) + '\n')
PY
}

prototype_owner() (
  set +e
  trap - ERR
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'prototype_finalize "$?"' EXIT
  prototype_finalize() {
    local status=$1
    trap - EXIT ERR
    trap '' INT TERM
    printf '%s\n' "$status" > "$SG_CASE/owner-status.txt"
    printf 'rollback entered\n' > "$SG_CASE/rollback-started"
    # Keep a bounded foreground rollback window for independently repeated signals.
    sleep 2
    if ! cp -P --preserve=mode,ownership,timestamps,xattr -- "$SG_CASE/fs/original" "$SG_CASE/fs/target/restore"; then
      capability_result "$CAPABILITY_CONTROL" FAIL
      exit "$status"
    fi
    if ! mv -T -- "$SG_CASE/fs/target/restore" "$SG_CASE/fs/target/value"; then
      capability_result "$CAPABILITY_CONTROL" FAIL
      exit "$status"
    fi
    if cmp -s "$SG_CASE/fs/original" "$SG_CASE/fs/target/value"; then
      capability_result "$CAPABILITY_CONTROL" PASS
    else
      capability_result "$CAPABILITY_CONTROL" FAIL
    fi
    printf 'rollback complete\n' > "$SG_CASE/rollback-complete"
    exit "$status"
  }
  cp -P --preserve=mode,ownership,timestamps,xattr -- "$SG_CASE/fs/target/value" "$SG_CASE/fs/original" || exit 252
  printf 'incoming\n' > "$SG_CASE/fs/target/publish"
  mv -T -- "$SG_CASE/fs/target/publish" "$SG_CASE/fs/target/value" || exit 252
  if [[ "$SG_ID" == CAP-EXIT ]]; then exit 252; fi
  python3 - "$BASHPID" << 'PY'
import json
import os
import pathlib
import sys
pid = int(sys.argv[1])
root = pathlib.Path(os.environ['SG_CASE'])
assert (root / 'fs/target/value').read_text() == 'incoming\n'
(root / 'barrier.json').write_text(json.dumps({'worker_pid': pid, 'pgid': os.getpgid(pid),
    'target': str(root / 'fs/target'), 'phase': 'foreground-after-real-leaf-rename'}) + '\n')
PY
  # Real foreground child, sharing the owned worker group, must terminate first.
  sleep 60
  exit 253
)

transaction_event() {
  python3 - "$@" << 'PY'
import json
import os
import pathlib
import sys
import time
record = {'phase': sys.argv[1], 'source': sys.argv[2], 'destination': sys.argv[3],
          'scenario': os.environ['SG_SCENARIO'], 'time_ns': time.monotonic_ns(),
          'pid': int(sys.argv[4]), 'fault': sys.argv[5] == 'fault'}
with (pathlib.Path(os.environ['SG_CASE']) / 'events.jsonl').open('a') as stream:
    stream.write(json.dumps(record) + '\n')
PY
}

transaction_barrier() {
  python3 - "$BASHPID" "$1" << 'PY'
import json
import os
import pathlib
import sys
root = pathlib.Path(os.environ['SG_CASE'])
store = root / 'var-lib/scripts-underground/release-deploy'
transactions = [path for path in store.glob('txn-*') if (path / 'state.json').is_file()]
latest = max(transactions, key=lambda path: path.stat().st_mtime_ns)
pid = int(sys.argv[1])
(root / 'barrier.json').write_text(json.dumps({'worker_pid': pid, 'pgid': os.getpgid(pid),
    'phase': sys.argv[2], 'transaction': str(latest), 'target': os.environ['SG_TARGET'],
    'marker': str(pathlib.Path(os.environ['HOME']) / ('.' + os.environ['SG_APP']))}) + '\n')
PY
  sleep 60
}

transaction_faults() {
  cp() {
    local from="${*: -2:1}" to="${*: -1}"
    if [[ "$SG_ID" == J8 && "$SG_FAULT" != none && "$to" == */entries/*/"$SG_FAULT" ]]; then
      transaction_event copy "$from" "$to" "$BASHPID" fault
      return 1
    elif [[ "$SG_ID" == J12 && "$SG_FAULT" != none && "$to" == */restore && "$(< "$from")" == 1.0.0 ]]; then
      transaction_event restore-copy "$from" "$to" "$BASHPID" fault
      return 1
    fi
    command cp "$@"
  }
  mv() {
    local from="${*: -2:1}" to="${*: -1}" new_state=''
    if [[ "$to" == */state.json && -f "$from" ]]; then new_state=$(jq -r '.state // empty' "$from"); fi
    if [[ "$SG_ID" == J11 && "$new_state" == COMMITTED ]]; then
      transaction_event commit "$from" "$to" "$BASHPID" fault
      return 1
    fi
    if [[ "$from" == */publish ]]; then
      if [[ "$SG_ID" == J10 && "$to" == "$HOME/.$SG_APP" ]]; then
        transaction_event marker "$from" "$to" "$BASHPID" fault
        return 1
      elif [[ "$SG_ID" == J13 ]]; then
        transaction_barrier before-publication
      fi
    fi
    if [[ "$SG_ID" == J17 && "$new_state" == APPLYING ]]; then
      transaction_event mutation-start "$from" "$to" "$BASHPID" ordinary
      sleep 0.2
    fi
    command mv "$@" || return "$?"
    if [[ "$from" == */publish ]]; then
      transaction_event publication "$from" "$to" "$BASHPID" ordinary
      if [[ "$SG_ID" == J9 && "$to" == "$SG_TARGET/value" ]]; then
        transaction_event after-alias-publication "$from" "$to" "$BASHPID" fault
        return 1
      elif [[ "$SG_ID" == J12 && "$SG_FAULT" != none && "$to" == "$HOME/.$SG_APP" ]]; then
        transaction_event after-marker-publication "$from" "$to" "$BASHPID" fault
        return 1
      elif [[ "$SG_ID" == J14 && "$to" == "$SG_TARGET/payload" ]]; then
        transaction_barrier after-payload
      elif [[ "$SG_ID" == J15 && "$to" == "$HOME/.$SG_APP" ]]; then
        transaction_barrier after-marker
      elif [[ "$SG_ID" == J22 && "$to" == "$SG_TARGET/payload" ]]; then
        printf 'external live edit\n' > "$to"
        transaction_event external-edit "$from" "$to" "$BASHPID" fault
        return 1
      fi
    fi
    if [[ "$SG_ID" == J16 && "$new_state" == COMMITTED ]]; then transaction_barrier after-committed; fi
    if [[ "$SG_ID" == J17 && "$new_state" == COMMITTED ]]; then
      transaction_event mutation-end "$from" "$to" "$BASHPID" ordinary
    fi
  }
}

transaction_cases() {
  local -a variants=(default)
  local variant root status first_status=0 retry_status=0 one two three before_traps after_traps
  case "$SG_ID" in
    J4) variants=(mount ancestor) ;;
    J5) variants=(aliases direct) ;;
    J6) variants=(external loop dangling directory) ;;
    J7) variants=(modified pruned) ;;
    J8) variants=(original incoming) ;;
    J20) variants=(external dangling loop fifo type) ;;
  esac
  printf '[]\n' > "$SG_CASE/scenarios.json"
  : > "$SG_CASE/events.jsonl"
  sg_load
  export SG_OBSERVE_ACTIVE=0
  transaction_faults
  trap ':' INT TERM
  for variant in "${variants[@]}"; do
    root="$SG_CASE/fs/$variant"
    mkdir "$root" "$root/target" "$root/source" "$root/source/app" "$root/backing"
    export SG_SCENARIO="$variant" SG_TARGET="$root/target" SG_APP="journal-${SG_ID,,}-$variant"
    export SG_OBSERVE_ACTIVE=0 SG_INVOCATION=primary
    export SG_FAULT="$variant"
    printf 'old payload\n' > "$SG_TARGET/payload"
    printf 'custom sentinel\n' > "$SG_TARGET/custom"
    printf 'old referent\n' > "$SG_TARGET/value"
    printf 'backing sentinel\n' > "$root/backing/witness"
    printf 'outside sentinel\n' > "$root/outside"
    printf 'incoming payload\n' > "$root/source/app/payload"
    printf 'fixture README\n' > "$root/source/app/README"
    printf '1.0.0\n' > "$HOME/.$SG_APP"
    export CLEAN_INSTALL=0
    case "$SG_ID" in
      J1)
        CLEAN_INSTALL=1
        mkdir "$SG_TARGET/obsolete" "$SG_TARGET/.root-dot-dir"
        printf 'nested dot\n' > "$SG_TARGET/obsolete/.nested"
        printf 'root dot\n' > "$SG_TARGET/.root-dot"
        printf 'root dot dir\n' > "$SG_TARGET/.root-dot-dir/value"
        ln -s chain "$SG_TARGET/alias"
        ln -s "$SG_TARGET/value" "$SG_TARGET/chain"
        printf 'incoming alias referent\n' > "$root/source/app/alias"
        chmod 751 "$SG_TARGET/payload"
        chown 65534:65534 "$SG_TARGET/payload"
        ;;
      J2 | J3 | J4)
        mkdir "$SG_TARGET/ancestor" "$SG_TARGET/ancestor/mounted"
        mount --bind "$root/backing" "$SG_TARGET/ancestor/mounted" || return 77
        printf 'eligible sibling\n' > "$SG_TARGET/ancestor/obsolete"
        if [[ "$SG_ID" == J2 ]]; then
          CLEAN_INSTALL=1
        elif [[ "$SG_ID" == J3 ]]; then
          mkdir "$root/source/app/ancestor" "$root/source/app/ancestor/mounted"
          printf 'old addressed leaf\n' > "$root/backing/addressed"
          printf 'new addressed leaf\n' > "$root/source/app/ancestor/mounted/addressed"
        elif [[ "$variant" == mount ]]; then
          mkdir "$root/source/app/ancestor"
          printf 'invalid mount replacement\n' > "$root/source/app/ancestor/mounted"
        else
          printf 'invalid ancestor replacement\n' > "$root/source/app/ancestor"
        fi
        ;;
      J5)
        ln -s "$SG_TARGET/value" "$SG_TARGET/alias-a"
        ln -s "$SG_TARGET/value" "$SG_TARGET/alias-b"
        printf 'one\n' > "$root/source/app/alias-a"
        if [[ "$variant" == aliases ]]; then printf 'two\n' > "$root/source/app/alias-b"; else printf 'two\n' > "$root/source/app/value"; fi
        ;;
      J6)
        ln -s "$root/outside" "$SG_TARGET/untouched"
        case "$variant" in
          external) ln -s "$root/outside" "$SG_TARGET/alias" ;;
          loop) ln -s alias "$SG_TARGET/alias" ;;
          dangling) ln -s absent "$SG_TARGET/alias" ;;
          directory)
            mkdir "$root/external-directory" "$root/source/app/alias"
            ln -s "$root/external-directory" "$SG_TARGET/alias"
            printf 'invalid write\n' > "$root/source/app/alias/child"
            ;;
        esac
        [[ "$variant" == directory ]] || printf 'invalid write\n' > "$root/source/app/alias"
        ;;
      J7)
        ln "$SG_TARGET/payload" "$root/hardlink"
        if [[ "$variant" == pruned ]]; then
          CLEAN_INSTALL=1
          rm "$root/source/app/payload"
        fi
        ;;
      J9)
        ln -s "$SG_TARGET/value" "$SG_TARGET/alias"
        printf 'incoming referent\n' > "$root/source/app/alias"
        ;;
      J10)
        CLEAN_INSTALL=1
        mkdir "$SG_TARGET/obsolete" "$SG_TARGET/obsolete/nested"
        printf 'nested original\n' > "$SG_TARGET/obsolete/nested/.original"
        chmod 710 "$SG_TARGET/obsolete/nested"
        chown 65534:65534 "$SG_TARGET/obsolete/nested"
        ;;
      J19)
        ln -s payload "$root/source/app/relative-link"
        ln -s value "$SG_TARGET/existing-link"
        chown -h 65534:65534 "$SG_TARGET/existing-link"
        ln -s payload "$root/source/app/existing-link"
        printf 'newline payload\n' > "$root/source/app/"$'line\nleaf\n'
        printf 'protected similarly spelled leaf\n' > "$SG_TARGET/"$'line\nleaf'
        ;;
      J20)
        case "$variant" in
          external) ln -s "$root/outside" "$root/source/app/link" ;;
          dangling) ln -s missing "$root/source/app/link" ;;
          loop) ln -s link "$root/source/app/link" ;;
          fifo) mkfifo "$root/source/app/special" ;;
          type)
            rm "$root/source/app/payload"
            mkdir "$root/source/app/payload"
            ;;
        esac
        ;;
      J21)
        mkdir "$root/previous-target"
        printf 'previous retained original\n' > "$root/previous-target/payload"
        _codeberg_deploy_tree "$root/source/app" "$root/previous-target" || return 2
        command cp -PR --preserve=mode,ownership,timestamps,xattr /var/lib/scripts-underground/release-deploy "$root/prior-store"
        mount -t tmpfs -o size=512k tmpfs /var/lib/scripts-underground/release-deploy || return 77
        chmod 700 /var/lib/scripts-underground /var/lib/scripts-underground/release-deploy
        command cp -PR --preserve=mode,ownership,timestamps,xattr "$root/prior-store/." /var/lib/scripts-underground/release-deploy/
        dd if=/dev/zero of="$SG_TARGET/payload" bs=1024 count=512 status=none
        ;;
    esac
    tar -czf "$root/release.tar.gz" -C "$root/source" app
    sg_release_routes codeberg safety/transaction v2.0.0 "$root/release.tar.gz" '' tarball
    sg_snapshot "$root/before.json" "target=$SG_TARGET" "backing=$root/backing" "outside=$root/outside" "marker=$HOME/.$SG_APP"
    findmnt --kernel --list --json --output ID,PARENT,MAJ:MIN,FSROOT,TARGET > "$root/mounts-before.json"
    stat -Lc '%d:%i' "$SG_TARGET" > "$root/root-before.txt"
    if [[ "$SG_ID" == J7 ]]; then
      sg_snapshot "$root/hardlink-before.json" "hardlink=$root/hardlink"
      stat -Lc '%d:%i:%h' "$root/hardlink" "$SG_TARGET/payload" > "$root/hardlink-identities-before.txt"
    fi
    before_traps=$(trap -p)
    export SG_OBSERVE_ACTIVE=1
    if [[ "$SG_ID" == J17 ]]; then
      mkdir "$root/alias" "$root/alias/nested"
      mount --bind "$SG_TARGET" "$root/alias/nested" || return 77
      fetch_and_deploy_codeberg_release "$SG_APP-one" safety/transaction tarball latest "$SG_TARGET" &
      one=$!
      fetch_and_deploy_codeberg_release "$SG_APP-two" safety/transaction tarball latest "$root/alias/nested" &
      two=$!
      fetch_and_deploy_codeberg_release "$SG_APP-three" safety/transaction tarball latest "$SG_TARGET" &
      three=$!
      status=0
      if wait "$one"; then call_status=0; else
        call_status=$?
        status=$call_status
      fi
      printf '%s\n' "$call_status" > "$root/one-status.txt"
      if wait "$two"; then call_status=0; else
        call_status=$?
        status=$call_status
      fi
      printf '%s\n' "$call_status" > "$root/two-status.txt"
      if wait "$three"; then call_status=0; else
        call_status=$?
        status=$call_status
      fi
      printf '%s\n' "$call_status" > "$root/three-status.txt"
    else
      if fetch_and_deploy_codeberg_release "$SG_APP" safety/transaction tarball latest "$SG_TARGET"; then status=0; else status=$?; fi
    fi
    if [[ "$SG_ID" == J12 ]]; then
      first_status=$status
      sg_review_capture "$variant-first" "$SG_TARGET/payload" "$HOME/.$SG_APP" > "$root/first-capture-path.txt"
      python3 - "$root" << 'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
store = pathlib.Path('/var/lib/scripts-underground/release-deploy')
(root / 'first-journal-states.json').write_text(json.dumps({path.name: json.loads((path / 'state.json').read_text())['state'] for path in store.glob('txn-*')}) + '\n')
PY
      SG_FAULT=none
      SG_INVOCATION=retry
      if fetch_and_deploy_codeberg_release "$SG_APP" safety/transaction tarball latest "$SG_TARGET"; then retry_status=0; else retry_status=$?; fi
      status=$retry_status
    elif [[ "$SG_ID" == J18 ]]; then
      first_status=$status
      sg_review_capture "$variant-success" "$SG_TARGET/payload" "$HOME/.$SG_APP" > "$root/success-capture-path.txt"
      printf '1.0.0\n' > "$HOME/.$SG_APP"
      SG_ID=J10
      SG_INVOCATION=failed-call
      if fetch_and_deploy_codeberg_release "$SG_APP" safety/transaction tarball latest "$SG_TARGET"; then retry_status=0; else retry_status=$?; fi
      SG_ID=J18
      status=$first_status
    fi
    after_traps=$(trap -p)
    sg_review_capture "$variant-final" "$SG_TARGET/payload" "$HOME/.$SG_APP" > "$root/final-capture-path.txt"
    export SG_OBSERVE_ACTIVE=0
    if [[ "$SG_ID" == J21 ]]; then
      command cp -PR --preserve=mode,ownership,timestamps,xattr /var/lib/scripts-underground/release-deploy "$root/capacity-store-evidence"
    fi
    printf '%s\n' "$before_traps" > "$root/traps-before.txt"
    printf '%s\n' "$after_traps" > "$root/traps-after.txt"
    sg_snapshot "$root/after.json" "target=$SG_TARGET" "backing=$root/backing" "outside=$root/outside" "marker=$HOME/.$SG_APP"
    stat -Lc '%d:%i' "$SG_TARGET" > "$root/root-after.txt"
    if [[ "$SG_ID" == J7 ]]; then
      sg_snapshot "$root/hardlink-after.json" "hardlink=$root/hardlink"
      stat -Lc '%d:%i:%h' "$root/hardlink" "$SG_TARGET/payload" > "$root/hardlink-identities-after.txt"
    fi
    findmnt --kernel --list --json --output ID,PARENT,MAJ:MIN,FSROOT,TARGET > "$root/mounts-after.json"
    python3 - "$root" "$status" "$first_status" "$retry_status" << 'PY'
import json
import os
import pathlib
import sys
case = pathlib.Path(os.environ['SG_CASE'])
records = json.loads((case / 'scenarios.json').read_text())
records.append({'variant': os.environ['SG_SCENARIO'], 'root': sys.argv[1], 'operation_status': int(sys.argv[2]),
                'first_status': int(sys.argv[3]), 'retry_status': int(sys.argv[4]), 'app': os.environ['SG_APP']})
(case / 'scenarios.json').write_text(json.dumps(records, indent=2) + '\n')
PY
  done
  sg_review_summary "$SG_CASE/before.json" before
  sg_review_summary "$SG_CASE/after.json" after
  printf '%s\n' "$status" > "$SG_CASE/operation-status.txt"
}

case "$SG_ID" in
  CAP-PRIMITIVES)
    mkdir "$SG_CASE/fs/target" "$SG_CASE/fs/backing" "$SG_CASE/fs/bind mount"
    printf 'old\n' > "$SG_CASE/fs/target/value"
    printf 'incoming\n' > "$SG_CASE/fs/target/publish"
    before_root=$(stat -Lc '%d:%i' "$SG_CASE/fs/target")
    incoming_inode=$(stat -Lc '%d:%i' "$SG_CASE/fs/target/publish")
    mv -T -- "$SG_CASE/fs/target/publish" "$SG_CASE/fs/target/value"
    [[ "$(< "$SG_CASE/fs/target/value")" == incoming ]]
    [[ "$(stat -Lc '%d:%i' "$SG_CASE/fs/target/value")" == "$incoming_inode" ]]
    [[ "$(stat -Lc '%d:%i' "$SG_CASE/fs/target")" == "$before_root" ]]
    # Verify NUL-delimited path reads before using them for journal consumers.
    unusual_path="$SG_CASE/fs/target/"$'line\nleaf\n'
    printf 'lossless path probe\n' > "$unusual_path"
    IFS= read -r -d '' read_path < <(realpath -e -z -- "$unusual_path")
    [[ "$read_path" == "$unusual_path" ]]
    encoded_path=$(jq -cn --arg path "$unusual_path" '{path:$path}')
    IFS= read -r -d '' read_path < <(jq -jr '.path + "\u0000"' <<< "$encoded_path")
    [[ "$read_path" == "$unusual_path" ]]
    capability_result exact-leaf-rename PASS
    printf 'metadata\n' > "$SG_CASE/fs/source"
    chmod 751 "$SG_CASE/fs/source"
    python3 - "$SG_CASE/fs/source" << 'PY'
import os
import sys
os.setxattr(sys.argv[1], 'user.su-capability', b'preserved-xattr')
os.utime(sys.argv[1], ns=(123000000000, 456000000000))
PY
    cp -P --preserve=mode,ownership,timestamps,xattr -- "$SG_CASE/fs/source" "$SG_CASE/fs/copied"
    python3 - "$SG_CASE/fs/source" "$SG_CASE/fs/copied" << 'PY'
import os
import pathlib
import sys
source, copy = map(pathlib.Path, sys.argv[1:])
a, b = source.stat(), copy.stat()
assert (a.st_mode, a.st_uid, a.st_gid, a.st_mtime_ns) == (b.st_mode, b.st_uid, b.st_gid, b.st_mtime_ns)
assert source.read_bytes() == copy.read_bytes()
assert os.getxattr(copy, 'user.su-capability') == b'preserved-xattr'
PY
    capability_result copy-metadata PASS
    ln -s source "$SG_CASE/fs/link"
    cp -P --preserve=mode,ownership,timestamps,xattr -- "$SG_CASE/fs/link" "$SG_CASE/fs/copied-link"
    [[ -L "$SG_CASE/fs/copied-link" && "$(readlink "$SG_CASE/fs/copied-link")" == source ]]
    capability_result copy-no-dereference PASS
    mount --bind "$SG_CASE/fs/backing" "$SG_CASE/fs/bind mount"
    findmnt --kernel --list --json --output ID,PARENT,MAJ:MIN,FSROOT,TARGET,SOURCE > "$SG_CASE/findmnt.json"
    python3 - << 'PY'
import json
import os
import pathlib
root = pathlib.Path(os.environ['SG_CASE'])
table = []
def decode(value):
    for encoded, plain in [('\\040', ' '), ('\\011', '\t'), ('\\012', '\n'), ('\\134', '\\')]:
        value = value.replace(encoded, plain)
    return value
for line in pathlib.Path('/proc/self/mountinfo').read_text().splitlines():
    fields = line.split()
    separator = fields.index('-')
    assert separator >= 6 and len(fields) >= separator + 4
    table.append({'id': int(fields[0]), 'parent': int(fields[1]), 'device': fields[2],
                  'origin': decode(fields[3]), 'target': decode(fields[4]),
                  'fstype': fields[separator + 1], 'source': decode(fields[separator + 2])})
target = str(root / 'fs/bind mount')
selected = [entry for entry in table if entry['target'] == target]
assert len(selected) == 1
entry = selected[0]
assert entry['origin'].endswith('/fs/backing')
assert os.stat(root / 'fs/backing').st_ino == os.stat(target).st_ino
reported = json.loads((root / 'findmnt.json').read_text())['filesystems']
found = [item for item in reported if item['target'] == target]
assert len(found) == 1
assert int(found[0]['id']) == entry['id'] and int(found[0]['parent']) == entry['parent']
assert found[0]['maj:min'] == entry['device'] and found[0]['fsroot'] == entry['origin']
(root / 'mountinfo-parsed.json').write_text(json.dumps(table, indent=2) + '\n')
PY
    capability_result mountinfo-bind-origins PASS
    capability_result findmnt-explicit-fields PASS
    exec {lock_fd}> "$SG_CASE/var-lib/lock"
    flock --exclusive --timeout 2 "$lock_fd"
    # Close the inherited lock descriptor so this is a genuinely independent contender.
    if (
      exec {lock_fd}>&-
      flock --exclusive --timeout 0.1 --conflict-exit-code 79 "$SG_CASE/var-lib/lock" true
    ); then
      capability_result flock-serialization FAIL
      exit 1
    else
      [[ "$?" == 79 ]]
    fi
    flock --unlock "$lock_fd"
    flock --exclusive --timeout 2 "$SG_CASE/var-lib/lock" true
    capability_result flock-serialization PASS
    ;;
  CAP-EXIT | CAP-INT | CAP-TERM)
    mkdir "$SG_CASE/fs/target"
    printf 'old\n' > "$SG_CASE/fs/target/value"
    CAPABILITY_CONTROL=exit-finalizer
    [[ "$SG_ID" != CAP-INT ]] || CAPABILITY_CONTROL=caught-int-finalizer
    [[ "$SG_ID" != CAP-TERM ]] || CAPABILITY_CONTROL=caught-term-finalizer
    # This test wrapper waits for its owner even when the whole owned group is signalled.
    trap ':' INT TERM
    if prototype_owner; then operation_rc=0; else operation_rc=$?; fi
    printf '%s\n' "$operation_rc" > "$SG_CASE/operation-status.txt"
    [[ -f "$SG_CASE/rollback-complete" ]]
    [[ "$(< "$SG_CASE/fs/target/value")" == old ]]
    [[ "$SG_ID" != CAP-EXIT ]] || exit 0
    exit "$operation_rc"
    ;;
  J*) transaction_cases ;;
  *)
    printf 'Unsupported transaction worker case: %s\n' "$SG_ID" >&2
    exit 2
    ;;
esac
