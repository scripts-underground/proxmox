#!/usr/bin/env bash
# Worker entry point: invoke through run-safety-gap-tests.sh, never on the host.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"
command -v 7z > /dev/null || exit 77
mkdir -p /opt/romm/frontend/dist/assets/emulatorjs/data/cores
mkdir -p /opt/romm/frontend/dist/assets/emulatorjs/custom
mkdir -p /opt/romm/frontend/dist/assets/ruffle/custom /opt/romm/backend
printf 'synthetic environment sentinel\n' > /opt/romm/.env
printf 'old loader\n' > /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js
printf 'old core\n' > /opt/romm/frontend/dist/assets/emulatorjs/data/cores/fixture.data
printf 'old ruffle\n' > /opt/romm/frontend/dist/assets/ruffle/ruffle.js
printf 'custom emulator save\n' > /opt/romm/frontend/dist/assets/emulatorjs/custom/save.dat
printf 'custom ruffle configuration\n' > /opt/romm/frontend/dist/assets/ruffle/custom/settings.json
printf '5.3.1\n' > "$HOME/.romm"
printf '4.2.3\n' > "$HOME/.emulatorjs"
printf '0.6.0\n' > "$HOME/.ruffle"
mkdir -p "$SG_CASE/assets/emulator-release/data/cores" "$SG_CASE/assets/ruffle-release"
printf 'incoming loader\n' > "$SG_CASE/assets/emulator-release/data/loader.js"
printf 'incoming core\n' > "$SG_CASE/assets/emulator-release/data/cores/fixture.data"
printf 'fixture license\n' > "$SG_CASE/assets/emulator-release/LICENSE"
printf 'incoming ruffle\n' > "$SG_CASE/assets/ruffle-release/ruffle.js"
printf 'fixture license\n' > "$SG_CASE/assets/ruffle-release/LICENSE"
(cd "$SG_CASE/assets" && 7z a "$SG_CASE/assets/emulator.7z" emulator-release > "$SG_CASE/archive-generation.log")
(cd "$SG_CASE/assets" && zip -qr "$SG_CASE/assets/ruffle.zip" ruffle-release)
case "$SG_ID" in
  R1) ;;
  R2 | R5) rm /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js ;;
  R3) rm -r /opt/romm/frontend/dist/assets/emulatorjs/data/cores ;;
  R4) rm /opt/romm/frontend/dist/assets/ruffle/ruffle.js ;;
  *) exit 2 ;;
esac
if [[ "$SG_ID" == R5 ]]; then
  printf 'deliberately corrupt synthetic archive\n' > "$SG_CASE/assets/emulator.7z"
fi
sg_release_routes github EmulatorJS/EmulatorJS v4.2.3 "$SG_CASE/assets/emulator.7z" 4.2.3.7z prebuild
sg_release_routes github ruffle-rs/ruffle v0.6.0 "$SG_CASE/assets/ruffle.zip" ruffle-0.6.0-web-selfhosted.zip prebuild
sg_snapshot "$SG_CASE/before.json" \
  env=/opt/romm/.env \
  emulator_custom=/opt/romm/frontend/dist/assets/emulatorjs/custom/save.dat \
  ruffle_custom=/opt/romm/frontend/dist/assets/ruffle/custom/settings.json \
  loader=/opt/romm/frontend/dist/assets/emulatorjs/data/loader.js \
  cores=/opt/romm/frontend/dist/assets/emulatorjs/data/cores \
  ruffle=/opt/romm/frontend/dist/assets/ruffle/ruffle.js \
  "romm_marker=$HOME/.romm" "emulator_marker=$HOME/.emulatorjs" "ruffle_marker=$HOME/.ruffle"
python3 - "$SG_SOURCE/scripts/lxc/romm.sh" "$SG_CASE/romm-definitions.sh" << 'PY'
import hashlib
import json
import os
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_bytes()
manifest = json.loads(pathlib.Path(os.environ['SG_MANIFEST']).read_text())
expected = next(entry['git_blob'] for entry in manifest['source']['inventory'] if entry['path'] == 'scripts/lxc/romm.sh')
assert hashlib.sha1(f'blob {len(source)}\0'.encode() + source).hexdigest() == expected
bootstrap = b'source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")\n'
assert source.count(bootstrap) == 1 and source.endswith(bootstrap)
pathlib.Path(sys.argv[2]).write_bytes(source[:-len(bootstrap)])
PY
sg_load
# shellcheck source=/dev/null
source "$SG_CASE/romm-definitions.sh"
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
setup_nodejs() { :; }
check_for_gh_release() { return 1; }
systemctl() { printf '%s\n' "$*" >> "$SG_CASE/systemctl-stub.log"; }
trap 'printf "%s\n" "$?" > "$SG_CASE/worker-exit.txt"' EXIT
trap -p > "$SG_CASE/traps.txt"
# The hook's exit ends only this supervisor-created worker, as in a real update.
update_script
