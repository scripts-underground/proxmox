#!/usr/bin/env bash
# This producer never sources the cleanup-under-test child's core/traps.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"
for app in autocaliweb endurain; do
  sg_make_tar "$SG_CASE/assets/$app.tar.gz" "README.md=fixture $app source\\n"
done
for app in forgejo readeck; do
  printf '#!/bin/sh\nprintf "%s version: 2.0.0\\n"\n' "$app" > "$SG_CASE/assets/$app"
  chmod 755 "$SG_CASE/assets/$app"
done
sg_release_routes codeberg gelbphoenix/autocaliweb v2.0.0 "$SG_CASE/assets/autocaliweb.tar.gz" '' tarball
sg_release_routes codeberg endurain-project/endurain v2.0.0 "$SG_CASE/assets/endurain.tar.gz" '' tarball
sg_release_routes codeberg forgejo/forgejo v2.0.0 "$SG_CASE/assets/forgejo" forgejo-2.0.0-linux-amd64 singlefile
sg_release_routes codeberg readeck/readeck v2.0.0 "$SG_CASE/assets/readeck" readeck-2.0.0-linux-amd64 singlefile
[[ "$SG_ID" == L1 || "$SG_ID" == L2 ]] || exit 2
if [[ "$SG_ID" == L2 ]]; then
  sg_add_route https://codeberg.org/api/v1/repos/endurain-project/endurain/releases 404 recognized-metadata-failure-after-autocaliweb
fi
printf 'protected unrelated temporary sibling\n' > /tmp/protected-sibling
sg_snapshot "$SG_CASE/before.json" protected_sibling=/tmp/protected-sibling
sg_transport_shims
export SG_ALLOC_EVENTS="$SG_CASE/diagnostic-allocations.jsonl"
bash -c '
  set -euo pipefail
  source "$SG_SOURCE/misc/tools.func"
  work=$(mktemp -d)
  trap '\''rm -rf "$work"'\'' EXIT
  trap -p EXIT > "$SG_CASE/diagnostic-trap-before.txt"
  source "$SG_SOURCE/misc/core.func"
  source "$SG_SOURCE/misc/error_handler.func"
  load_functions
  trap -p EXIT > "$SG_CASE/diagnostic-trap-after.txt"
' > "$SG_CASE/trap-diagnostic.log" 2>&1
export SG_ALLOC_EVENTS="$SG_CASE/live-allocations.jsonl"
# exec starts the unchanged test with its own traps; none are reinstalled here.
exec bash "$SG_SOURCE/tests/codeberg-release.test.sh" --live
