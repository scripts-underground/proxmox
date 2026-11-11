#!/usr/bin/env bash
# Actual bundle writer, cold hook/config bytes and service-side config readback.
# free, apk, OpenRC and surrounding framework lifecycle are explicit models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/etc" /etc
  source "$c/hooks.sh"
  source "$ROOT/misc/bundle.func"
  # shellcheck disable=SC2034
  NSAPP=alpine-valkey
  # The receiver uses its own explicit disk-backed temporary root.
  export var_lxc_tmpdir="$c/tmp"
  role=install hook=install_script
  pipeline=(install_script)
  if [[ "$VARIANT" == update ]]; then
    role=update hook=update_script
    pipeline=('run_update_script "$@"')
  fi
  _write_bundle "$role" "$hook" "$c/cache" --script-id alpine-valkey -- --requirements 1 256 -- "${pipeline[@]}" > "$c/$role"
  cp "$c/$role" "$c/generated-bundle"
  # Start a different cold receiver, without the creator's exported memory.
  receiver=()
  [[ "$VARIANT" != receiver-conflict ]] || receiver=(MEMTOTAL_MB=1048576 MAXMEMORY_MB=999999999)
  exec env -i PATH="$PATH" ROOT="$ROOT" HOME="$HOME" CASE_ROOT="$c" VARIANT="$VARIANT" \
    FREE_STATUS="$FREE_STATUS" FIXTURE_AWK_BIN="$FIXTURE_AWK_BIN" VERBOSE="$VERBOSE" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
    "${receiver[@]}" bash "$c/$role"
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
# The private /etc intentionally has no Debian alternatives links. Keep the
# actual native parser executable rather than modeling it or changing the hook.
awk_bin=$(realpath "$(command -v awk)")
work=$(mktemp -d "$TMPDIR/alpine-valkey.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for variant in 256 512 1024 257 2 creator-conflict receiver-conflict malformed zero one missing duplicate negative decimal leading-zero oversized expression failed update; do
    c="$work/$mode-$variant"
    mkdir -p "$c/"{etc/valkey,cache,home,tmp}
    printf 'USER existing config\n' > "$c/etc/valkey/valkey.conf"
    cp "$c/etc/valkey/valkey.conf" "$c/before"
    : > "$c/events"
    : > "$c/messages"
    memory=256 limit=192 expected=0 free_status=0
    case "$variant" in
      512) memory=512 limit=384 ;;
      1024) memory=1024 limit=768 ;;
      257) memory=257 ;;
      2) memory=2 limit=1 ;;
      malformed) memory=garbage expected=65 ;;
      zero) memory=0 expected=65 ;;
      one) memory=1 expected=65 ;;
      missing | duplicate) expected=65 ;;
      negative) memory=-256 expected=65 ;;
      decimal) memory=256.5 expected=65 ;;
      leading-zero) memory=0256 expected=65 ;;
      oversized) memory=999999999999999999999999 expected=65 ;;
      expression) memory='1+255' expected=65 ;;
      failed) free_status=23 expected=65 ;;
      update) memory=garbage ;;
    esac
    printf '              total used free shared buff/cache available\nMem: %s 0 0 0 0 0\nSwap: 0 0 0\n' "$memory" > "$c/free-output"
    [[ "$variant" != missing ]] || printf 'Swap: 0 0 0\n' > "$c/free-output"
    [[ "$variant" != duplicate ]] || printf 'Mem: 512 0 0 0 0 0\n' >> "$c/free-output"
    printf 'maxmemory %smb\nmaxmemory-policy allkeys-lru\nmaxmemory-samples 10\n' "$limit" > "$c/expected"
    [[ "$variant" != update ]] || cp "$c/before" "$c/expected"
    sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/alpine-valkey.sh" > "$c/hooks.sh"
    cat > "$c/models.sh" << 'MODELS'
source "$ROOT/misc/core.func"
load_functions
msg_info() { printf '%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_ok() { printf '%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_error() { printf '%s\n' "$*" >&2; }
header_info() { :; }
run_update_script() { update_script; }
awk() { "$FIXTURE_AWK_BIN" "$@"; }
free() {
  printf 'free:%s\n' "$*" >> "$CASE_ROOT/events"
  [[ "$*" == -m ]] || return 64
  cat "$CASE_ROOT/free-output"
  return "$FREE_STATUS"
}
apk() {
  # Configuration publication must still follow the original package step.
  cmp /etc/valkey/valkey.conf "$CASE_ROOT/before" || return 76
  printf 'apk:%s\n' "$*" >> "$CASE_ROOT/events"
}
rc-update() {
  cmp /etc/valkey/valkey.conf "$CASE_ROOT/expected" || return 77
  printf 'rc-update:%s\n' "$*" >> "$CASE_ROOT/events"
}
rc-service() {
  cmp /etc/valkey/valkey.conf "$CASE_ROOT/expected" || return 78
  cp /etc/valkey/valkey.conf "$CASE_ROOT/service-readback"
  printf 'rc-service:%s\n' "$*" >> "$CASE_ROOT/events"
}
MODELS
    # Use the real writer and real silent wrapper, with the same modeled cache
    # boundary as the existing Readarr fixture. No package/network bootstrapping.
    printf 'load_functions() { source "$CASE_ROOT/models.sh"; }\ncolor() { :; }\n' > "$c/cache/core.func"
    printf 'catch_errors() { :; }\n' > "$c/cache/error_handler.func"
    printf 'setup_lxc() { :; }\n' > "$c/cache/install.func"
    printf 'setup_uv() { :; }\n' > "$c/cache/tools.func"
    printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/cache/github.func"
    creator=()
    [[ "$variant" != creator-conflict ]] || creator=(MEMTOTAL_MB=1048576 MAXMEMORY_MB=999999999)
    rc=0
    env -i PATH="$PATH" ROOT="$ROOT" HOME="$c/home" TMPDIR="$c/tmp" CASE_ROOT="$c" VARIANT="$variant" \
      FREE_STATUS="$free_status" FIXTURE_AWK_BIN="$awk_bin" VERBOSE="$mode" "${creator[@]}" \
      timeout 20s unshare -mn --propagation private -- bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?
    label="Alpine-Valkey/$mode/$variant"
    check "$rc" "$expected" "$label actual generated cold bundle status"
    [[ "$rc" == "$expected" ]] || tail -n 5 "$c/output"
    if [[ "$expected" != 0 ]]; then
      check "$(cmp -s "$c/etc/valkey/valkey.conf" "$c/before" && printf retained || printf changed)" retained "$label prior config unchanged"
      check "$(cat "$c/events")" 'free:-m' "$label no package/config/service effects before refusal"
      check "$(test -e "$c/service-readback" && printf present || printf absent)" absent "$label service not reached"
      check "$(grep -Ec 'Unable to determine receiver memory|too small for a positive Valkey maxmemory' "$c/output" || true)" 1 "$label actionable memory refusal"
    else
      check "$(cmp -s "$c/etc/valkey/valkey.conf" "$c/expected" && printf match || printf mismatch)" match "$label exact config consumer bytes"
      check "$(cmp -s "$c/service-readback" "$c/expected" && printf match || printf mismatch)" match "$label modeled service reads actual config"
      if [[ "$variant" == update ]]; then
        check "$(cat "$c/events")" "$(printf 'apk:-U upgrade\nrc-service:valkey restart')" "$label unchanged updater has no memory probe or config write"
      else
        check "$(cat "$c/events")" "$(printf 'free:-m\napk:add valkey\nrc-update:add valkey default\nrc-service:valkey start')" "$label measurement/package/config/service ordering"
      fi
    fi
    check "$(grep -Ec '^declare -- (MEMTOTAL_MB|MAXMEMORY_MB)=' "$c/generated-bundle" || true)" 0 "$label creator memory is not baked"
    if [[ "$variant" == update ]]; then
      check "$(test -f "$c/update" && printf retained || printf missing)" retained "$label generated updater remains installed"
    else
      check "$(test -e "$c/install" && printf present || printf absent)" absent "$label generated installer self-removes"
    fi
  done
done
printf '%s failure(s); actual generated cold bundles/config bytes; free/apk/OpenRC/framework lifecycle modeled, no native Alpine deployment claim\n' "$failures"
[[ "$failures" == 0 ]]
