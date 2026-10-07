#!/usr/bin/env bash
# Exact route dispatch is shared by current/legacy isolated checker workers.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"
export SG_APP="safety-${SG_ID,,}-$SG_VARIANT"
case "$SG_ID" in
  P1)
    request=1.0.0
    upstream=v1.0.0
    ;;
  P2 | P3)
    request=v1.0.0
    upstream=1.0.0
    ;;
  P4)
    request=version/2
    upstream=version/2
    ;;
  P5)
    request=v1.0.0
    upstream=1.0.0
    ;;
  P6)
    request=1.0.0
    upstream=v1.0.0
    ;;
  P7)
    request=1.0.0
    upstream=v2.0.0
    ;;
  *) exit 2 ;;
esac
sg_release_routes codeberg safety/pins "$upstream" '' '' metadata
printf '%s' "$request" > "$SG_CASE/request.txt"
printf '%s' "$upstream" > "$SG_CASE/upstream.txt"
if [[ "$upstream" == v1.0.0 ]]; then
  sg_add_route https://codeberg.org/api/v1/repos/safety/pins/releases/tags/1.0.0 404 missing-unprefixed-tag
elif [[ "$upstream" == 1.0.0 ]]; then
  sg_add_route https://codeberg.org/api/v1/repos/safety/pins/releases/tags/v1.0.0 404 missing-prefixed-tag
fi
[[ "$SG_ID" != P3 ]] || printf '1.0.0\n' > "$HOME/.$SG_APP"
if [[ "$SG_ID" == P5 || "$SG_ID" == P7 ]]; then
  python3 - << 'PY'
import json
import os
import pathlib
path = pathlib.Path(os.environ['SG_ROUTES'])
routes = json.loads(path.read_text())
api = 'https://codeberg.org/api/v1/repos/safety/pins/releases'
if os.environ['SG_ID'] == 'P5':
    routes[api] = {'json': [{'draft': False, 'prerelease': False, 'tag_name': 'v99.0.0', 'assets': []}]}
else:
    routes[api + '/tags/1.0.0'] = routes[api + '/tags/v2.0.0']
path.write_text(json.dumps(routes, indent=2) + '\n')
PY
fi
if [[ "$SG_ID" == P6 || "$SG_ID" == P7 ]]; then printf '1.0.0\n' > "$HOME/.$SG_APP"; fi
sg_snapshot "$SG_CASE/before.json" "marker=$HOME/.$SG_APP"
sg_load
CHECK_UPDATE_RELEASE=stale-selection
if [[ "$SG_ID" == P6 ]]; then
  printf '[]\n' > "$SG_CASE/lookup-results.json"
  for failure in auth network; do
    python3 - "$failure" << 'PY'
import json
import os
import pathlib
import sys
path = pathlib.Path(os.environ['SG_ROUTES'])
routes = json.loads(path.read_text())
routes['https://codeberg.org/api/v1/repos/safety/pins/releases/tags/1.0.0'] = {
    'status': 401 if sys.argv[1] == 'auth' else 200, 'curl_status': 0 if sys.argv[1] == 'auth' else 18,
    'json': {'message': 'recognized ' + sys.argv[1] + ' failure'}, 'recognized_error': sys.argv[1]}
path.write_text(json.dumps(routes, indent=2) + '\n')
PY
    CHECK_UPDATE_RELEASE=stale-selection
    if check_for_codeberg_release "$SG_APP" safety/pins "$request"; then operation_rc=0; else operation_rc=$?; fi
    python3 - "$failure" "$operation_rc" "${CHECK_UPDATE_RELEASE:-}" << 'PY'
import json
import os
import pathlib
import sys
path = pathlib.Path(os.environ['SG_CASE']) / 'lookup-results.json'
records = json.loads(path.read_text())
records.append({'failure': sys.argv[1], 'operation_status': int(sys.argv[2]), 'selection': sys.argv[3]})
path.write_text(json.dumps(records, indent=2) + '\n')
PY
  done
  printf '%s\n' "$operation_rc" > "$SG_CASE/operation-status.txt"
  printf '%s' "${CHECK_UPDATE_RELEASE:-}" > "$SG_CASE/selected-release.txt"
  sg_snapshot "$SG_CASE/after.json" "marker=$HOME/.$SG_APP"
  exit 0
fi
if check_for_codeberg_release "$SG_APP" safety/pins "$request"; then
  operation_rc=0
else
  operation_rc=$?
fi
printf '%s\n' "$operation_rc" > "$SG_CASE/operation-status.txt"
printf '%s' "${CHECK_UPDATE_RELEASE:-}" > "$SG_CASE/selected-release.txt"
sg_snapshot "$SG_CASE/after.json" "marker=$HOME/.$SG_APP"
