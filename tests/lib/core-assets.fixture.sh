#!/usr/bin/env bash
# Real decoding/publication/git consumers; transport, package manager and init are models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/core-assets.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/payload" "$work/live"
sed "s|/tmp/gl_rel.json|$work/gl_rel.json|g" "$ROOT/misc/tools.func" > "$work/subject.func"
source "$work/subject.func"
source "$ROOT/misc/github.func"
export HOME="$work/home" STD=''
msg_info() { :; }
msg_ok() { :; }
msg_warn() { printf '%s\n' "$*" >> "$work/diagnostics"; }
msg_error() { printf '%s\n' "$*" >> "$work/diagnostics"; }
ensure_dependencies() { :; }
getent() { return 0; }
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
scenario=normal
asset=probe.gz
curl_download() {
  if [[ "$scenario" == transfer ]]; then
    printf partial > "$1"
    return 18
  fi
  command cp -- "$work/payload/$asset" "$1"
}
curl() {
  local out='' url=''
  while (($#)); do
    case "$1" in
      -o)
        out="$2"
        shift
        ;;
      https:*) url="$1" ;;
    esac
    shift
  done
  if [[ "$url" == *api.github.com* || "$url" == *codeberg.org/api/* ]]; then
    command jq -cn --arg url "https://fixture.invalid/$asset" '{tag_name:"v1.2.3",draft:false,prerelease:false,assets:[{browser_download_url:$url}]}' > "$out"
    printf 200
  elif [[ "$url" == *gitlab.com/api/* ]]; then
    command jq -cn --arg url "https://fixture.invalid/$asset" '{tag_name:"v1.2.3",assets:{links:[{direct_asset_url:$url}]}}' > "$out"
    printf 200
  else curl_download "$out" "$url"; fi
}
printf '#!/bin/sh\nprintf "decoded-consumer\\n"\n' > "$work/payload/probe"
gzip -c "$work/payload/probe" > "$work/payload/probe.gz"
bzip2 -c "$work/payload/probe" > "$work/payload/probe.bz2"
xz -c "$work/payload/probe" > "$work/payload/probe.xz"
zstd -q -c "$work/payload/probe" > "$work/payload/probe.zst"
printf 'jar archive bytes' > "$work/payload/probe.jar"
tar -czf "$work/payload/probe.tar.gz" -C "$work/payload" probe
for provider in gh codeberg gl; do
  for suffix in gz bz2 xz zst; do
    asset="probe.$suffix"
    FORCE_DEPLOY=1 USE_ORIGINAL_FILENAME=true "fetch_and_deploy_${provider}_release" probe owner/probe singlefile v1.2.3 "$work/live" "$asset"
    rc=0
    value=$("$work/live/probe" 2> /dev/null) || rc=$?
    check "$rc/$value" '0/decoded-consumer' "F12 $provider $suffix actual decoded executable consumer"
    rm -f -- "$work/live/probe" "$work/live/$asset"
  done
  asset=probe.jar
  FORCE_DEPLOY=1 USE_ORIGINAL_FILENAME=true "fetch_and_deploy_${provider}_release" probe owner/probe singlefile v1.2.3 "$work/live" "$asset"
  check "$(cat "$work/live/probe.jar")/$(stat -c %a "$work/live/probe.jar")" 'jar archive bytes/644' "F12 $provider jar remains nonexecutable and unmodified"
  asset=probe.tar.gz
  FORCE_DEPLOY=1 USE_ORIGINAL_FILENAME=true "fetch_and_deploy_${provider}_release" probe owner/probe singlefile v1.2.3 "$work/live" "$asset"
  check "$(sha256sum < "$work/live/probe.tar.gz")" "$(sha256sum < "$work/payload/probe.tar.gz")" "F12 $provider tarball is not decoded as a binary"
  for scenario in corrupt transfer; do
    asset=broken.gz
    printf broken > "$work/payload/$asset"
    printf previous > "$work/live/probe"
    chmod 751 "$work/live/probe"
    printf previous-marker > "$HOME/.probe"
    rc=0
    FORCE_DEPLOY=1 "fetch_and_deploy_${provider}_release" probe owner/probe singlefile v1.2.3 "$work/live" "$asset" || rc=$?
    check "$((rc != 0))" 1 "F12 $provider $scenario reports failure"
    check "$(cat "$work/live/probe")/$(stat -c %a "$work/live/probe")/$(cat "$HOME/.probe")" 'previous/751/previous-marker' "F12 $provider $scenario preserves executable and marker"
  done
  scenario=normal
done

asset=elf
/usr/bin/cp /bin/echo "$work/payload/$asset"
rc=0
fetch_and_deploy_from_url 'https://fixture.invalid/download?token=opaque' "$work/live" elf-probe || rc=$?
value=$("$work/live/elf-probe" elf-consumer 2> /dev/null) || true
check "$rc/$value" '0/elf-consumer' 'F13 real ELF executable with explicit destination'
fetch_and_deploy_from_url 'https://fixture.invalid/elf?query=opaque' "$work/live" || true
check "$(test -x "$work/live/elf" && echo yes || echo no)" yes 'F13 default filename excludes query'
for name in '../outside' '/absolute' '.' '..' 'a/b' $'bad\nname'; do
  rc=0
  fetch_and_deploy_from_url 'https://fixture.invalid/elf' "$work/live" "$name" || rc=$?
  check "$rc" 65 "F13 rejects destination $name"
done
asset=probe.jar
rc=0
fetch_and_deploy_from_url 'https://fixture.invalid/apparently-executable' "$work/live" not-elf || rc=$?
check "$rc" 65 'F13 filename does not make arbitrary bytes executable'

cp() {
  [[ "$scenario" != copy-fail ]] || return 41
  command cp "$@"
}
chmod() {
  [[ "$scenario" != mode-fail ]] || return 42
  command chmod "$@"
}
mv() {
  [[ "$scenario" != rename-fail ]] || return 43
  command mv "$@"
}
for scenario in copy-fail mode-fail rename-fail; do
  printf retained > "$work/live/probe"
  rc=0
  _deploy_single_file "$work/payload/probe" probe "$work/live" probe || rc=$?
  check "$rc/$(cat "$work/live/probe")" '252/retained' "F12/F13 $scenario leaves old consumer intact"
  check "$(find "$work/live" -name '.asset-file.*' -print)" '' "F12/F13 $scenario removes only its stage"
done
unset -f cp chmod mv
scenario=normal

# Git transport uses a real local repository; only the remote address is replaced.
/usr/bin/git init -q --initial-branch main "$work/remote"
/usr/bin/git -C "$work/remote" -c user.name=Fixture -c user.email=fixture@example.invalid config commit.gpgsign false
printf new-source > "$work/remote/code"
printf vendor > "$work/remote/config"
/usr/bin/git -C "$work/remote" add .
/usr/bin/git -C "$work/remote" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial
git() {
  local -a args=("$@")
  local i
  for i in "${!args[@]}"; do
    [[ "${args[i]}" != https://github.com/owner/probe.git ]] || args[i]="file://$work/remote"
  done
  if [[ "$scenario" == clone-fail && "${args[0]}" == clone ]]; then
    mkdir -p "${args[-1]}"
    printf partial > "${args[-1]}/partial"
    return 44
  elif [[ "$scenario" == checkout-fail && " ${args[*]} " == *' checkout '* ]]; then return 45; fi
  command git "${args[@]}"
}
mkdir -p "$work/checkout/data"
printf operator > "$work/checkout/config"
printf durable > "$work/checkout/data/value"
printf obsolete > "$work/checkout/old"
rc=0
CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP='config data' clone_and_deploy_gh_commit probe owner/probe main '' '' "$work/checkout" || rc=$?
check "$rc" 0 'F2 clone publishes into existing target through checked replacement'
check "$(cat "$work/checkout/code" 2> /dev/null || true)/$(cat "$work/checkout/config")/$(cat "$work/checkout/data/value")/$(test -e "$work/checkout/old" && echo present || echo absent)" 'new-source/operator/durable/absent' 'F2 source replacement preserves declared paths and removes obsolete source'
for scenario in clone-fail checkout-fail; do
  printf old-code > "$work/checkout/code"
  printf old-marker > "$HOME/.probe"
  rc=0
  clone_and_deploy_gh_commit probe owner/probe main '' bad-ref "$work/checkout" || rc=$?
  check "$rc" "$([[ "$scenario" == clone-fail ]] && echo 44 || echo 45)" "F2 $scenario preserves exact producer status under conditional callers"
  check "$(cat "$work/checkout/code")/$(cat "$HOME/.probe")" 'old-code/old-marker' "F2 $scenario preserves live source and marker"
done
scenario=normal
printf branch-update > "$work/remote/code"
command git -C "$work/remote" add .
command git -C "$work/remote" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm update
rc=0
CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP='config data' git_update_checkout "$work/checkout" branch main || rc=$?
check "$rc/$(cat "$work/checkout/code")/$(cat "$work/checkout/config")/$(cat "$work/checkout/data/value")" '0/branch-update/operator/durable' 'F2 clean branch update uses a staged checkout without git clean'

# The package lifecycle owner must enclose BOTH primary and fallback before init.
dpkg-deb() {
  if [[ "$1" == -f ]]; then printf su-fixture; else
    tar -cf - -C "$work/package" etc
  fi
}
mkdir -p "$work/package/etc/systemd/system"
printf unit > "$work/package/etc/systemd/system/probe.service"
dpkg-query() { printf 'su-fixture\t%s\n' "$fixture_installed"; }
_diagnose_deb_failure() { :; }
systemctl() {
  printf '%s\n' "$*" >> "$work/init-calls"
  case "$1" in
    show)
      printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=%s\n' "$fixture_active" "$fixture_enabled"
      return "$query_rc"
      ;;
    daemon-reload) return 0 ;;
    start | restart) return "$service_rc" ;;
  esac
  return 86
}
apt() {
  printf 'apt %s offline=%s\n' "$*" "${SYSTEMD_OFFLINE:-}" >> "$work/package-calls"
  return "$apt_rc"
}
dpkg() {
  printf 'dpkg %s offline=%s\n' "$*" "${SYSTEMD_OFFLINE:-}" >> "$work/package-calls"
  return "$dpkg_rc"
}
for adapter in github codeberg gitlab url; do
  for state in fresh active stopped disabled; do
    fixture_installed=installed fixture_active=inactive fixture_enabled=enabled query_rc=0 service_rc=0 apt_rc=0 dpkg_rc=0
    case "$state" in fresh) fixture_installed=not-installed ;; active) fixture_active=active ;; disabled) fixture_installed=not-installed fixture_enabled=disabled ;; esac
    : > "$work/init-calls"
    : > "$work/package-calls"
    rc=0
    _deploy_release_deb "$work/package.deb" "$adapter" || rc=$?
    check "$rc" 0 "F14 $adapter $state package owner status"
    expected=''
    if [[ "$adapter" != url ]]; then
      case "$state" in fresh) expected='start -- probe.service' ;; active) expected='restart -- probe.service' ;; esac
    fi
    check "$(grep -E '^(start|restart) ' "$work/init-calls" || true)" "$expected" "F14 $adapter $state lifecycle outcome"
  done
done
fixture_installed=installed fixture_active=active fixture_enabled=enabled
for fault in fallback package query service; do
  apt_rc=0 dpkg_rc=0 query_rc=0 service_rc=0 expected=0
  case "$fault" in fallback) apt_rc=42 ;; package) apt_rc=42 dpkg_rc=47 expected=100 ;; query) query_rc=49 expected=49 ;; service) service_rc=50 expected=50 ;; esac
  : > "$work/init-calls"
  : > "$work/package-calls"
  rc=0
  _deploy_release_deb "$work/package.deb" github || rc=$?
  check "$rc" "$expected" "F14 $fault exact terminal status"
  if [[ "$fault" == package || "$fault" == query ]]; then
    check "$(grep -E '^(start|restart) ' "$work/init-calls" || true)" '' "F14 $fault never reaches service effects"
  elif [[ "$fault" == service ]]; then
    check "$(grep -c '^dpkg ' "$work/package-calls" || true)" 0 'F14 restart failure never triggers dpkg fallback'
  fi
done
printf 'CORE_ASSETS_RESULT failures=%s\n' "$failures"
((failures == 0))
