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
sleep() { :; }
curl() {
  local out=''
  while (($#)); do
    if [[ "$1" == -o ]]; then
      out="$2"
      shift
    fi
    shift
  done
  command cp "$work/$input.asc" "$out"
  [[ "$fault" != network ]] || return 18
}
cp() {
  if [[ "$fault" == write ]]; then
    printf 'partial stage' > "${@: -1}"
    return 71
  fi
  command cp "$@"
}
chmod() {
  [[ "$fault" != mode ]] || return 72
  command chmod "$@"
}
chown() {
  [[ "$fault" != owner ]] || return 73
  command chown "$@"
}
mv() {
  [[ "$fault" != publish ]] || return 74
  command mv "$@"
}
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in dearmor binary auto; do
  for fault in none network invalid truncated write mode owner publish; do
    # Processing write faults are exercised by binary/auto copy, not a mock GPG.
    [[ "$fault" != write || "$mode" == binary ]] || continue
    c="$work/$mode-$fault"
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
    download_gpg_key https://fixture.invalid/key.asc "$c/key.gpg" "$mode" || rc=$?
    expected=7
    [[ "$fault" != none ]] || expected=0
    check "$rc" "$expected" "$mode/$fault public key helper status"
    if [[ "$fault" != none ]]; then
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
  done
done
fault=none input=valid
download_gpg_key https://fixture.invalid/key.asc "$work/new.gpg" dearmor
check "$(stat -c %a "$work/new.gpg")" 644 'fresh key remains apt-readable'
printf '%s failure(s); native GPG key consumer and publication metadata; curl/faults modeled\n' "$failures"
[[ "$failures" == 0 ]]
