#!/usr/bin/env bash
# Worker entry point for synthetic filesystem topology/fault fixtures.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"
export SG_TARGET="$SG_CASE/fs/target" SG_BACKING="$SG_CASE/fs/backing"
export SG_APP="safety-${SG_ID,,}-$SG_VARIANT"
mkdir "$SG_TARGET" "$SG_BACKING"
printf 'old payload\n' > "$SG_TARGET/payload"
printf 'custom sentinel\n' > "$SG_TARGET/custom"
printf 'mounted backing sentinel\n' > "$SG_BACKING/witness"
printf '1.0.0\n' > "$HOME/.$SG_APP"
case "$SG_ID" in
  C3 | C4)
    printf 'old referent\n' > "$SG_TARGET/value"
    ln -s "$SG_TARGET/value" "$SG_TARGET/alias"
    sg_make_tar "$SG_CASE/assets/release.tar.gz" 'alias=incoming payload\n' 'README=fixture\n'
    ;;
  C5)
    cp "$SG_TARGET/payload" "$SG_BACKING/payload"
    cp "$SG_TARGET/custom" "$SG_BACKING/custom"
    mount --bind "$SG_BACKING" "$SG_TARGET" || exit 77
    sg_make_tar "$SG_CASE/assets/release.tar.gz" 'payload=incoming payload\n' 'README=fixture\n'
    ;;
  C6)
    mkdir "$SG_TARGET/data"
    mount --bind "$SG_BACKING" "$SG_TARGET/data" || exit 77
    sg_make_tar "$SG_CASE/assets/release.tar.gz" 'payload=incoming payload\n' 'README=fixture\n'
    ;;
  C1 | C2 | C7)
    sg_make_tar "$SG_CASE/assets/release.tar.gz" 'payload=incoming payload\n' 'README=fixture\n'
    ;;
  *) exit 2 ;;
esac
findmnt -n -o TARGET,SOURCE,PROPAGATION --target "$SG_TARGET" > "$SG_CASE/mount-topology.txt"
sg_release_routes codeberg safety/fixture v2.0.0 "$SG_CASE/assets/release.tar.gz" '' tarball
sg_snapshot "$SG_CASE/before.json" "target=$SG_TARGET" "backing=$SG_BACKING" "marker=$HOME/.$SG_APP"
sg_load
if [[ "$SG_ID" == C2 ]]; then
  mv() {
    local source="${*: -2:1}" destination="${*: -1}"
    if [[ "$SG_SOURCE_ROLE" == candidate && "$source" == */publish && "$destination" == "$SG_TARGET/payload" ]]; then
      [[ -f "$SG_TARGET/README" ]] || return 98
      printf 'real earlier README publication, then returned payload publication fault\n' > "$SG_CASE/fault-observed.txt"
      return 1
    elif [[ "$SG_SOURCE_ROLE" == baseline && "${1:-}" == -T && "${2:-}" == */new && "${3:-}" == "$SG_TARGET" ]]; then
      printf 'returned publication fault\n' > "$SG_CASE/fault-observed.txt"
      return 1
    fi
    command mv "$@"
  }
elif [[ "$SG_ID" == C4 ]]; then
  cp() {
    local source="${*: -2:1}" destination="${*: -1}"
    if [[ "$SG_SOURCE_ROLE" == candidate && "$source" == */staging/extract/*/alias && "$destination" == */entries/*/incoming ]]; then
      command cp "$@" || return "$?"
      printf 'delegated real alias incoming preparation, then returned failure\n' > "$SG_CASE/fault-observed.txt"
      return 1
    elif [[ "$SG_SOURCE_ROLE" == baseline && "${1:-}" == -r && "${2:-}" == */. && -f "${2%/.}/alias" ]]; then
      command cp -r "${2%/.}/alias" "$3/alias" || return "$?"
      printf 'delegated real first payload copy, then returned failure\n' > "$SG_CASE/fault-observed.txt"
      return 1
    fi
    command cp "$@"
  }
elif [[ "$SG_ID" == C7 ]]; then
  mv() {
    local source="${*: -2:1}" destination="${*: -1}"
    if [[ "$SG_SOURCE_ROLE" == candidate && "$source" == */publish && "$destination" == "$SG_TARGET/payload" ]]; then
      command mv "$@" || return "$?"
      trap -p > "$SG_CASE/barrier-traps.txt"
      python3 - "$BASHPID" << 'PY'
import json
import os
import pathlib
import sys
pid = int(sys.argv[1])
root = pathlib.Path(os.environ['SG_CASE'])
target = pathlib.Path(os.environ['SG_TARGET'])
store = root / 'var-lib/scripts-underground/release-deploy'
unfinished = [path for path in store.glob('txn-*') if json.loads((path / 'state.json').read_text())['state'] == 'APPLYING']
assert len(unfinished) == 1
transaction = unfinished[0]
plan = json.loads((transaction / 'plan.json').read_text())
payload = next(item for item in plan if item['path'] == str(target / 'payload'))
marker = next(item for item in plan if item['action'] == 'marker')
assert (transaction / f'entries/{payload["id"]}/original').read_text() == 'old payload\n'
assert (transaction / f'entries/{marker["id"]}/original').read_text() == '1.0.0\n'
assert target.is_dir() and (target / 'payload').read_text() == 'incoming payload\n'
event = {'worker_pid': pid, 'pgid': os.getpgid(pid), 'target': str(target),
         'transaction': str(transaction), 'canonical_root_present': True,
         'old_payload_backup': str(transaction / f'entries/{payload["id"]}/original'),
         'old_marker_backup': str(transaction / f'entries/{marker["id"]}/original')}
(root / 'barrier.json').write_text(json.dumps(event, indent=2) + '\n')
PY
      sleep 60
      return 98
    elif [[ "$SG_SOURCE_ROLE" == baseline && "${1:-}" == -T && "${2:-}" == "$SG_TARGET" && "${3:-}" == */previous ]]; then
      command mv "$@" || return "$?"
      trap -p > "$SG_CASE/barrier-traps.txt"
      python3 - "$BASHPID" "$3" << 'PY'
import json
import os
import pathlib
import sys
pid = int(sys.argv[1])
previous = pathlib.Path(sys.argv[2])
assert not pathlib.Path(os.environ['SG_TARGET']).exists() and (previous / 'payload').is_file()
event = {'worker_pid': pid, 'pgid': os.getpgid(pid), 'target': os.environ['SG_TARGET'],
         'previous': str(previous), 'old_payload': (previous / 'payload').read_text(),
         'cmdline': pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode()}
(pathlib.Path(os.environ['SG_CASE']) / 'barrier.json').write_text(json.dumps(event, indent=2) + '\n')
PY
      while :; do sleep 1; done
    fi
    command mv "$@"
  }
fi
if fetch_and_deploy_codeberg_release "$SG_APP" safety/fixture tarball latest "$SG_TARGET"; then
  operation_rc=0
else
  operation_rc=$?
fi
printf '%s\n' "$operation_rc" > "$SG_CASE/operation-status.txt"
sg_snapshot "$SG_CASE/after.json" "target=$SG_TARGET" "backing=$SG_BACKING" "marker=$HOME/.$SG_APP"
