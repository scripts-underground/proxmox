#!/usr/bin/env bash
# Actual release helper/cold hooks/checksum/tar/ELF and writer-generated bundles.
# HTTP transport, architecture detection, APT and service effects are models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/units" /etc/systemd/system
  mount --bind /var/lib/scripts-underground "$c/state/scripts-underground"
  mount --rbind "$c/state" /var/lib
  source "$ROOT/misc/tools.func"
  source "$c/hooks.sh"
  if [[ "$ROLE" == bundle || "$ROLE" == install-bundle ]]; then
    source "$ROOT/misc/bundle.func"
    # shellcheck disable=SC2034
    NSAPP=readarr
    if [[ "$ROLE" == install-bundle ]]; then
      _write_bundle install install_script "$c/cache" --script-id readarr -- --requirements 2 1024 -- \
        'source "$CASE_ROOT/install-before.sh"' install_script 'source "$CASE_ROOT/install-after.sh"' > "$c/install"
      exec bash "$c/install"
    fi
    # The pre-existing updater model supplies its receiving path explicitly.
    export var_lxc_tmpdir="$TMPDIR"
    _write_bundle update update_script "$c/cache" --script-id readarr -- --requirements 2 1024 -- 'run_update_script "$@"' > "$c/update"
    exec bash "$c/update"
  fi
  source "$c/models.sh"
  trap 'printf retained > "$CASE_ROOT/exit-trap"' EXIT
  trap ':' ERR
  before=$(trap -p EXIT ERR RETURN)
  rc=0
  install_script || rc=$?
  [[ "$(trap -p EXIT ERR RETURN)" == "$before" ]] || exit 96
  printf retained > "$c/traps"
  exit "$rc"
fi

: "${TMPDIR:?disk-backed TMPDIR required}" "${MAINTENANCE_REFERENCES:?immutable archives required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/readarr-release.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for variant in x64 arm64 corrupt download extract unsupported bundle receiver-default receiver-absent receiver-override receiver-invalid; do
    arch=amd64
    [[ "$variant" != arm64 && "$variant" != receiver-override ]] || arch=arm64
    [[ "$variant" != unsupported ]] || arch=riscv64
    c="$work/$mode-$variant"
    mkdir -p "$c/"{opt,units,state/scripts-underground,cache,home,tmp,legacy}
    printf lookalike > "$c/tmp/readarr-existing"
    for name in packages services events downloads; do : > "$c/$name"; done
    # Drop the transport footer. Only forbidden historical /tmp literals are
    # disk-mapped for the old-code RED; no guest RAM path is ever written.
    sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/readarr.sh" | sed "s|/tmp/readarr|$c/legacy/readarr|g" > "$c/hooks.sh"
    cat > "$c/models.sh" << 'MODELS'
source "$ROOT/misc/core.func"
load_functions
msg_info() { printf '%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_ok() { printf '%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_dependencies() { :; }
getent() { return 0; }
dpkg() { printf '%s\n' "$TEST_ARCH"; }
uname() { if [[ "$TEST_ARCH" == amd64 ]]; then printf 'x86_64\n'; else printf 'aarch64\n'; fi; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
run_update_script() { update_script; }
apt() { printf '%s\n' "$*" >> "$CASE_ROOT/packages"; }
systemctl() { printf '%s\n' "$*" >> "$CASE_ROOT/services"; }
curl() {
  local out='' url='' format=''
  while (($#)); do
    case "$1" in
      -o) out="$2"; shift ;;
      -w) format="$2"; shift ;;
      https:*) url="$1" ;;
    esac
    shift
  done
  printf '%s\n' "$url" >> "$CASE_ROOT/api"
  [[ "$url" == https://api.github.com/repos/Readarr/Readarr/releases/tags/v0.4.18.2805 ]] || return 64
  local body='{"tag_name":"v0.4.18.2805","draft":false,"prerelease":true,"assets":[' sep='' asset
  for asset in Readarr.develop.0.4.18.2805.linux-core-{x64,arm64}.tar.gz; do
    body+="$sep{\"name\":\"$asset\",\"browser_download_url\":\"https://github.com/Readarr/Readarr/releases/download/v0.4.18.2805/$asset\"}"
    sep=,
  done
  body+=']}'
  if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
  [[ -z "$format" ]] || printf 200
}
curl_download() {
  printf 'download\n' >> "$CASE_ROOT/events"
  printf '%s\n' "$2" >> "$CASE_ROOT/downloads"
  printf '%s|%s|%s\n' "$TMPDIR" "$HOME" "$1" >> "$CASE_ROOT/transport-context"
  [[ "$VARIANT" != download ]] || return 22
  cp -- "$MAINTENANCE_REFERENCES/readarr/${2##*/}" "$1"
  [[ "$VARIANT" != corrupt ]] || printf CORRUPT >> "$1"
}
sha256sum() { printf 'sha\n' >> "$CASE_ROOT/events"; command sha256sum "$@"; }
tar() {
  printf 'tar\n' >> "$CASE_ROOT/events"
  [[ "$VARIANT" != extract ]] || return 73
  command tar "$@"
}
get_system_arch > "$CASE_ROOT/default-arch"
MODELS
    printf 'load_functions() { source "$CASE_ROOT/models.sh"; }\ncolor() { :; }\n' > "$c/cache/core.func"
    printf 'catch_errors() { :; }\n' > "$c/cache/error_handler.func"
    printf 'setup_lxc() { :; }\n' > "$c/cache/install.func"
    cp "$ROOT/misc/tools.func" "$c/cache/tools.func"
    printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/cache/github.func"
    role=install
    if [[ "$variant" == bundle ]]; then
      role=bundle
      mkdir -p "$c/state/readarr" "$c/opt/Readarr"
      printf existing-app > "$c/opt/Readarr/Readarr"
    elif [[ "$variant" == receiver-* ]]; then
      role=install-bundle
      # Observe source-time receiving state after the real writer's unmodified
      # validation/preparation prelude, before models or application effects.
      printf 'printf "%%s\\n" "${TMPDIR-unset}" > "$CASE_ROOT/prelude-receiver"\nsetup_lxc() { :; }\n' > "$c/cache/install.func"
      printf 'printf "%%s\\n" "$TMPDIR" > "$CASE_ROOT/hook-receiver"\ntrap -p EXIT ERR RETURN > "$CASE_ROOT/traps-before"\n' > "$c/install-before.sh"
      printf 'trap -p EXIT ERR RETURN > "$CASE_ROOT/traps-after"\ncmp "$CASE_ROOT/traps-before" "$CASE_ROOT/traps-after"\nprintf retained > "$CASE_ROOT/traps"\n' > "$c/install-after.sh"
    fi
    rc=0
    receiving=()
    case "$variant" in
      receiver-override) receiving=("var_lxc_tmpdir=$c/receiving space") ;;
      receiver-invalid) receiving=(var_lxc_tmpdir=relative) ;;
    esac
    creator=("TMPDIR=$c/tmp")
    [[ "$variant" != receiver-absent ]] || creator=()
    env -i PATH="$PATH" ROOT="$ROOT" HOME="$c/home" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" CASE_ROOT="$c" ROLE="$role" VARIANT="$variant" TEST_ARCH="$arch" VERBOSE="$mode" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
      "${receiving[@]}" "${creator[@]}" timeout 90s unshare -mn --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$variant" in corrupt) expected=1 ;; download) expected=250 ;; extract) expected=73 ;; unsupported | receiver-invalid) expected=65 ;; esac
    label="Readarr/$mode/$variant"
    check "$rc" "$expected" "$label cold status"
    if [[ "$rc" != "$expected" ]]; then tail -n 5 "$c/output"; fi
    if [[ "$variant" == receiver-invalid ]]; then
      check "$(test -e "$c/prelude-receiver" && printf reached || printf absent)" absent "$label refuses before library source effects"
      check "$(stat -c %s "$c/packages")" 0 "$label refuses before package effects"
      check "$(stat -c %s "$c/downloads")" 0 "$label refuses before download"
      check "$(stat -c %s "$c/services")" 0 "$label refuses before service"
      check "$(test -e "$c/opt/Readarr" && printf present || printf absent)" absent "$label refuses before deployment"
      rm -rf -- "$c"
      continue
    fi
    check "$(cat "$c/default-arch")" "$arch" "$label generic dpkg default retained"
    check "$(cat "$c/tmp/readarr-existing")" lookalike "$label caller temporary data retained"
    check "$(find "$c/tmp" -mindepth 1 -maxdepth 1 ! -name readarr-existing | wc -l)" 0 "$label owned stages cleaned"
    if [[ "$variant" == bundle ]]; then
      check "$(cat "$c/packages")" "$(printf 'update\n-y upgrade')" "$label actual generated updater is APT-only"
      check "$(cat "$c/opt/Readarr/Readarr")" existing-app "$label updater leaves app bytes unchanged"
      check "$(stat -c %s "$c/services")" 0 "$label updater does not restart app"
      check "$(stat -c %s "$c/downloads")" 0 "$label updater does not download app"
      check "$(grep -c 'does not update Readarr' "$c/messages" || true)" 2 "$label truthful updater messages"
    else
      check "$(cat "$c/traps" 2> /dev/null || true)" retained "$label caller traps unchanged"
      if [[ "$role" == install-bundle ]]; then
        receiver=/var/lib/readarr/tmp physical="$c/state/readarr/tmp"
        [[ "$variant" != receiver-override ]] || {
          receiver="$c/receiving space"
          physical="$receiver"
        }
        check "$(cat "$c/prelude-receiver" 2> /dev/null || true)" "$receiver" "$label source declaration reaches pre-library context"
        check "$(cat "$c/hook-receiver" 2> /dev/null || true)" "$receiver" "$label actual hook consumes receiver path"
        check "$(stat -c %a "$physical" 2> /dev/null || true)" 1777 "$label real framework prepares sticky receiver"
        check "$(find "$physical" -mindepth 1 -maxdepth 1 2> /dev/null | wc -l)" 0 "$label helper and archive stages cleaned on receiver"
        check "$(test -e "$c/install" && printf present || printf absent)" absent "$label generated install EXIT trap self-removes"
        context_ok=no
        if [[ -s "$c/transport-context" ]]; then
          IFS='|' read -r temporary home destination < "$c/transport-context"
          [[ "$temporary" == "$receiver"/readarr.* && "$home" == "$temporary" && "$destination" == "$temporary"/download/* ]] && context_ok=yes
        fi
        check "$context_ok" yes "$label real helper staging is receiver-owned"
      else
        check "$(cat "$c/exit-trap" 2> /dev/null || true)" retained "$label original EXIT trap executes"
      fi
      check "$(cat "$c/packages")" 'install -y sqlite3 libicu-dev' "$label dependencies unchanged"
      if [[ "$expected" == 0 ]]; then
        alias=x64 machine=62
        [[ "$arch" != arm64 ]] || {
          alias=arm64
          machine=183
        }
        check "$(cat "$c/downloads")" "https://github.com/Readarr/Readarr/releases/download/v0.4.18.2805/Readarr.develop.0.4.18.2805.linux-core-$alias.tar.gz" "$label exact official asset"
        check "$(cat "$c/events")" "$(printf 'download\nsha\ntar')" "$label real hash precedes extraction"
        elf=missing
        if [[ -f "$c/opt/Readarr/Readarr" ]]; then elf=$(
          python3 - "$c/opt/Readarr/Readarr" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);raw=p.read_bytes()[:20]
assert raw[:6]==b'\x7fELF\x02\x01' and p.stat().st_mode&0o111
print(int.from_bytes(raw[18:20],'little'))
PY
        ); fi
        check "$elf" "$machine" "$label real extracted ELF machine (not application execution)"
        check "$(cat "$c/services")" "$(printf '%s\n' '-q daemon-reload' 'enable --now -q readarr')" "$label original service lifecycle"
        check "$(grep -c '^ExecStart=/opt/Readarr/Readarr -nobrowser -data=/var/lib/readarr/' "$c/units/readarr.service")" 1 "$label original root unit paths"
        check "$(test ! -e "$c/home/.readarr" && printf private)" private "$label helper marker stays private"
      else
        check "$(test -e "$c/opt/Readarr" && printf present || printf absent)" absent "$label failed input cannot deploy"
        check "$(stat -c %s "$c/services")" 0 "$label failed input cannot start service"
        if [[ "$variant" != extract ]]; then check "$(grep -c '^tar$' "$c/events" || true)" 0 "$label refusal before extraction"; fi
      fi
    fi
    rm -rf -- "$c"
  done
done
printf '%s failure(s); actual official archive checksum/tar/ELF and generated OS-only updater; transport/APT/systemd modeled; no native Readarr or ARM runtime claim\n' "$failures"
[[ "$failures" == 0 ]]
