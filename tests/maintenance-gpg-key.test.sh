#!/usr/bin/env bash
# Real GPG and filesystem publication; curl and explicit filesystem failures
# are modeled. No live system keyrings are touched.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}" "${GPG_FIXTURE:?provide a valid public key}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-gpg.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -m 700 "$work/gnupg" "$work/tmp"
export GNUPGHOME="$work/gnupg" TMPDIR="$work/tmp" CURL_RETRIES=1
gpg --batch --no-default-keyring --keyring "$GPG_FIXTURE" --armor --export > "$work/valid.asc"
gpg --batch --show-keys "$work/valid.asc" > /dev/null 2>&1
printf 'not a key\n' > "$work/invalid.asc"
# Retain the header and a plausible beginning, but remove the key's body/footer.
python3 - "$work/valid.asc" "$work/truncated.asc" << 'PY'
import pathlib,sys
b=pathlib.Path(sys.argv[1]).read_bytes();pathlib.Path(sys.argv[2]).write_bytes(b[:len(b)//2])
PY
source "$ROOT/misc/tools.func"
debug_log() { :; }
msg_warn() { printf '%s\n' "$*" >&2; }
sleep() { :; }
curl() {
  local calls
  calls=$(< "$work/calls")
  calls=$((calls + 1))
  printf '%s\n' "$calls" > "$work/calls"
  local out=''
  while (($#)); do
    if [[ "$1" == -o ]]; then
      out="$2"
      shift
    fi
    shift
  done
  command cp "$work/$input.asc" "$out"
  if [[ "$fault" == network || ("$fault" == retry && "$calls" == 1) ]]; then
    printf 'curl: (18) end of response with 123 bytes missing\n' >&2
    return 18
  fi
  if [[ "$fault" == secret ]]; then
    printf 'curl: (28) Connection timed out for https://user:password@fixture.invalid/key?token=SECRET\n' >&2
    printf '\033[31mKEY_BYTES_DO_NOT_PRINT %060000d\n' 0 >&2
    return 28
  fi
}
cp() {
  if [[ "$fault" == write ]]; then
    printf 'partial stage' > "${@: -1}"
    printf 'cp: error writing private stage: No space left on device\n' >&2
    return 71
  fi
  command cp "$@"
}
chmod() {
  [[ "$fault" != mode ]] || {
    printf 'chmod: Permission denied\n' >&2
    return 72
  }
  command chmod "$@"
}
chown() {
  [[ "$fault" != owner ]] || {
    printf 'chown: Operation not permitted\n' >&2
    return 73
  }
  command chown "$@"
}
mv() {
  [[ "$fault" != publish ]] || {
    printf 'mv: Read-only file system\n' >&2
    return 74
  }
  command mv "$@"
}
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
# The external writer uses native SIGPIPE behavior: a short-reading capture
# without draining cannot hide the producer's death behind a later return.
expected_capture=$(printf '%04096d' 0)
capture_rc=0
captured=$(_gpg_key_diagnostic python3 -c '
import signal, sys
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
sys.stderr.buffer.write(b"0" * 4096 + b"1" * 131072)
sys.stderr.buffer.flush()
sys.exit(23)
') || capture_rc=$?
check "$captured" "$expected_capture" 'diagnostic captures exactly the first 4096 stderr bytes'
check "$capture_rc" 23 'diagnostic drains remaining stderr and preserves producer status'
for caller in quiet verbose; do
  for mode in dearmor binary auto; do
    for fault in none network invalid truncated write mode owner publish retry secret; do
      # Processing write faults are exercised by binary/auto copy, not a mock GPG.
      [[ "$fault" != write || "$mode" == binary ]] || continue
      c="$work/$caller-$mode-$fault"
      mkdir -p "$c"
      command cp "$GPG_FIXTURE" "$c/key.gpg"
      command chmod 0640 "$c/key.gpg"
      command chown 0:65534 "$c/key.gpg"
      before=$(sha256sum "$c/key.gpg")
      before=${before%% *}
      metadata=$(stat -c '%a:%u:%g' "$c/key.gpg")
      input=valid
      case "$fault" in invalid | truncated) input="$fault" ;; esac
      rc=0
      calls=0 CURL_RETRIES=1
      printf '0\n' > "$work/calls"
      [[ "$fault" != retry ]] || CURL_RETRIES=3
      # Same conditional contract as quiet silent/verbose passthrough callers.
      if [[ "$caller" == quiet ]]; then
        download_gpg_key 'https://user:password@fixture.invalid/key?token=SECRET' "$c/key.gpg" "$mode" > "$c/stdout" 2> "$c/diagnostic" || rc=$?
      else
        download_gpg_key 'https://user:password@fixture.invalid/key?token=SECRET' "$c/key.gpg" "$mode" > "$c/stdout" 2> >(tee "$c/diagnostic" >&2) || rc=$?
        wait
      fi
      expected=7
      [[ "$fault" != none && "$fault" != retry ]] || expected=0
      check "$rc" "$expected" "$mode/$fault public key helper status"
      check "$(wc -c < "$c/stdout")" 0 "$caller/$mode/$fault stdout stays quiet"
      diagnostic=$(< "$c/diagnostic")
      if [[ "$expected" == 0 ]]; then
        check "$diagnostic" '' "$caller/$mode/$fault success has no warning"
      else
        check "$(wc -l < "$c/diagnostic")" 1 "$caller/$mode/$fault one final diagnostic"
        case "$fault" in
          network) cause='(18)|partial|missing|incomplete' ;;
          invalid | truncated) cause='OpenPGP|packet|radix64|CRC|EOF|eof|invalid|empty' ;;
          write) cause='No space left|space|full' ;;
          mode) cause='Permission denied|permission' ;;
          owner) cause='Operation not permitted|permitted|permission' ;;
          publish) cause='Read-only file system|read-only' ;;
          secret) cause='(28)|timed out|timeout' ;;
        esac
        observed=no
        if grep -Eiq "$cause" "$c/diagnostic"; then observed=yes; fi
        check "$observed" yes "$caller/$mode/$fault actual failing command cause reaches caller"
        check "$(LC_ALL=C tr -d '\12\40-\176' < "$c/diagnostic" | wc -c)" 0 "$caller/$mode/$fault diagnostic has no control bytes"
      fi
      safe=yes
      if grep -Eq 'password|SECRET|KEY_BYTES|https?://' "$c/diagnostic"; then safe=no; fi
      check "$safe" yes "$caller/$mode/$fault no URL credentials or key bytes in diagnostic"
      bounded=no
      if [[ $(wc -c < "$c/diagnostic") -le 512 ]]; then bounded=yes; fi
      check "$bounded" yes "$caller/$mode/$fault diagnostic bounded to 512 bytes"
      expected_calls=1
      [[ "$fault" != retry ]] || expected_calls=2
      check "$(< "$work/calls")" "$expected_calls" "$caller/$mode/$fault no extra network probe and normal retry"
      if [[ "$expected" != 0 ]]; then
        after=$(sha256sum "$c/key.gpg")
        after=${after%% *}
        check "$after" "$before" "$mode/$fault last-known-good key bytes preserved"
      fi
      check "$(stat -c '%a:%u:%g' "$c/key.gpg")" "$metadata" "$mode/$fault existing key mode/owner preserved"
      command chmod 0755 "$c"
      readable=no
      if KEY_DIR="$c" unshare -m --propagation private -- sh -c 'mount --bind "$KEY_DIR" /mnt; setpriv --reuid=65534 --regid=65534 --clear-groups test -r /mnt/key.gpg'; then readable=yes; fi
      check "$readable" yes "$mode/$fault native nonroot group reader retains access"
      rc=0
      gpg --batch --show-keys "$c/key.gpg" > "$c/show-output" 2>&1 || rc=$?
      check "$rc" 0 "$mode/$fault real consumer can still parse installed public key"
      count=$(find "$c" -mindepth 1 -maxdepth 1 -name '.gpg-key.*' | wc -l)
      check "$count" 0 "$mode/$fault no abandoned publication stage"
      check "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type f | wc -l)" 0 "$caller/$mode/$fault no abandoned temporary diagnostics or key"
    done
  done
done
fault=none input=valid
calls=0 CURL_RETRIES=1
printf '0\n' > "$work/calls"
download_gpg_key https://fixture.invalid/key.asc "$work/new.gpg" dearmor
check "$(stat -c %a "$work/new.gpg")" 644 'fresh key remains apt-readable'
# Observe the real framework message/log boundary and both STD forms. Only its
# UI spinner is replaced; no services or shared spinner files are involved.
source "$ROOT/misc/core.func"
trap - HUP INT TERM
trap 'rm -rf -- "$work"' EXIT
stop_spinner() { :; }
YWB='' CL='' INFO='WARN'
for STD in silent ''; do
  for fault in network retry; do
    c="$work/wrapper-${STD:-verbose}-$fault"
    mkdir -p "$c"
    INSTALL_LOG="$c/active.log" _HOST_LOGFILE=''
    printf '0\n' > "$work/calls"
    input=valid CURL_RETRIES=3 rc=0
    $STD download_gpg_key 'https://user:password@fixture.invalid/key?token=SECRET' "$c/key.gpg" dearmor > "$c/stdout" 2> "$c/stderr" || rc=$?
    expected=7
    [[ "$fault" != retry ]] || expected=0
    check "$rc" "$expected" "${STD:-verbose}/$fault real caller status"
    check "$(wc -c < "$c/stdout")" 0 "${STD:-verbose}/$fault real caller stdout quiet"
    if [[ "$fault" == network ]]; then
      check "$(grep -c '\[WARN\].*incomplete download' "$c/active.log")" 1 "${STD:-verbose} failure cause reaches actual final log consumer"
      check "$(< "$work/calls")" 3 "${STD:-verbose} exhausted retry count preserved"
    else
      check "$(wc -c < "$c/stderr")" 0 "${STD:-verbose} recovered retry has no warning"
      rc=0
      gpg --batch --show-keys "$c/key.gpg" > /dev/null 2>&1 || rc=$?
      check "$rc" 0 "${STD:-verbose} recovered retry publishes real parseable key"
    fi
  done
done
printf '%s failure(s); native GPG key consumer and publication metadata; curl/faults modeled\n' "$failures"
[[ "$failures" == 0 ]]
