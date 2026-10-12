#!/usr/bin/env bash
# Run inside a disposable guest with Angie and Python installed.
# Proves archive deployment and the generated proxy config, not the RomM UI.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
source "$ROOT/misc/tools.func"
load_functions

if [[ "${1:-}" == --setup ]]; then
  setup_deb822_repo \
    angie \
    https://angie.software/keys/angie-signing.gpg \
    "https://download.angie.software/angie/debian/$(get_os_info version_id)" \
    "$(get_os_info codename)" \
    main
  $STD apt install -y angie python3 p7zip-full
  exit 0
fi

work=$(mktemp -d)
cleanup() {
  if [[ -s "$work/angie.pid" ]]; then
    angie -s quit -c "$work/angie.conf" -p "$work" || true
    wait "${server_pid:-}" 2> /dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
export INSTALL_LOG="$work/install.log" HOME="$work/home"
mkdir "$HOME"

test ! -e /opt/romm/frontend/dist/index.html
VERBOSE=no set_std_mode
fetch_and_deploy_gh_release EmulatorJS EmulatorJS/EmulatorJS prebuild v4.2.3 \
  /opt/romm/frontend/dist/assets/emulatorjs '4.2.3.7z'
test -s /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js
grep -q 'Everything is Ok' "$INSTALL_LOG"
printf 'PASS .7z deployment and quiet-mode extraction log\n'

VERBOSE=yes set_std_mode
fetch_and_deploy_gh_release ruffle ruffle-rs/ruffle prebuild latest \
  /opt/romm/frontend/dist/assets/ruffle 'ruffle-*-web-selfhosted.zip'
test -s /opt/romm/frontend/dist/assets/ruffle/ruffle.js
printf 'PASS GitHub ZIP regression\n'

fetch_and_deploy_gh_release uv-probe astral-sh/uv prebuild 0.12.13 \
  "$work/uv" 'uv-x86_64-unknown-linux-gnu.tar.gz'
"$work/uv/uv" --version | grep -q '0.12.13'
printf 'PASS GitHub TAR regression\n'

python3 - "$ROOT/scripts/lxc/romm.sh" "$work" << 'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
work = pathlib.Path(sys.argv[2])
start = "cat << 'EOF' > /etc/angie/http.d/romm.conf\n"
config = source.split(start, 1)[1].split("\nEOF", 1)[0]
config = config.replace("listen 80;", "listen 8080;")
(work / "angie.conf").write_text(
    f"daemon off;\npid {work}/angie.pid;\n"
    f"error_log {work}/error.log;\nevents {{}}\nhttp {{\n{config}\n}}\n"
)
pathlib.Path("/opt/romm/frontend/dist/index.html").write_text(
    "<!doctype html><title>RomM proxy fixture</title>\n"
)
PY
angie -t -c "$work/angie.conf" -p "$work"
angie -c "$work/angie.conf" -p "$work" &
server_pid=$!
for ((attempt = 0; attempt < 30; attempt++)); do
  if curl -fsS http://127.0.0.1:8080/ -o "$work/page"; then
    break
  fi
  sleep 0.2
done

for route in /rom/1/ejs /rom/36/ejs '/rom/36/ejs?test=1'; do
  curl -fsS -D "$work/headers" "http://127.0.0.1:8080$route" -o "$work/page"
  cmp /opt/romm/frontend/dist/index.html "$work/page"
  grep -qi '^Cross-Origin-Embedder-Policy: require-corp' "$work/headers"
  grep -qi '^Cross-Origin-Opener-Policy: same-origin' "$work/headers"
done
printf 'PASS player routes serve SPA HTML with both isolation headers\n'

for route in / /settings /index.html; do
  curl -fsS -D "$work/headers" "http://127.0.0.1:8080$route" -o "$work/page"
  cmp /opt/romm/frontend/dist/index.html "$work/page"
  if grep -qi '^Cross-Origin-' "$work/headers"; then
    printf 'unexpected isolation header on normal SPA route\n' >&2
    exit 1
  fi
done
printf 'PASS ordinary SPA route regression\n'

core=$(find /opt/romm/frontend/dist/assets/emulatorjs/data/cores -name '*dosbox_pure*.data' -print -quit)
test -n "$core"
for file in /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js "$core"; do
  url="${file#/opt/romm/frontend/dist}"
  curl -fsS "http://127.0.0.1:8080$url" -o "$work/asset"
  cmp "$file" "$work/asset"
done
printf 'PASS deployed loader and DOS core served byte-for-byte\n'
