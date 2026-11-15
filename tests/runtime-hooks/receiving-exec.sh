#!/usr/bin/env bash
# Actual customization and repair regions of build_container with the actual receiving-context
# owner. The CT is a model: pct exec keeps the creator environment (PVE keep-env default) and runs
# the command with a distro PATH of shims/real tools; package managers are shims that use TMPDIR
# like a package script. Alpine runs in BusyBox ash when ALPINE_BUSYBOX is provided, otherwise in
# the system sh (labeled). RECEIVING_EXEC_OWNER_ROOT may name another tree to reproduce an older owner.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  # shellcheck source=/dev/null
  source "$OWNER_ROOT/misc/bundle.func"
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf 'warn: %s\n' "${1:-}"; }
  msg_error() { printf 'error: %s\n' "${1:-}"; }
  msg_custom() { :; }
  # shellcheck disable=SC2034
  TAB='' HOLD='' YW='' CL='' BFR='' CM='' GN='' RD='' DGN='' BL=''
  sleep() { :; }
  read() {
    printf 'prompt\n' >> "$c/events"
    builtin read "$@"
  }
  pct() {
    printf '%s\n' "$2" >> "$c/pcts"
    [[ "$1" == exec && "$3" == -- ]] || return 97
    shift 3
    if [[ -n "${ASH:-}" ]]; then
      case "$1" in /bin/sh | sh | ash) set -- "$ASH" sh "${@:2}" ;; esac
    fi
    env PATH="$CTBIN" "$@"
  }
  # shellcheck source=/dev/null
  source "$c/region.sh"
  export CTID=2225
  # shellcheck disable=SC2034
  tz=UTC LANG=C.UTF-8
  if [[ "$MODE" == repair ]]; then fn=run_repair; else fn=run_customize; fi
  [[ "${HAS_ROOT:-no}" != yes ]] || export var_lxc_tmpdir="$RECEIVER"
  [[ "${HAS_ROOT:-no}" != empty ]] || export var_lxc_tmpdir=
  trap 'printf "CREATOR_TMPDIR_AFTER=%s\n" "${TMPDIR-unset}" > "$c/creator-after"' EXIT
  "$fn"
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
OWNER_ROOT=$(realpath -e "${RECEIVING_EXEC_OWNER_ROOT:-$ROOT}")
work=$(mktemp -d "$TMPDIR/receiving-exec.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
count() { grep -c -- "$1" "$2" || true; }
BF="$OWNER_ROOT/misc/build.func"

# name, os, mode, root, consumer
cases=(
  'alpine alpine customize root apk'
  'debian debian customize root apt-get'
  'ubuntu ubuntu customize root apt-get'
  'devuan devuan customize root apt-get'
  'fedora fedora customize root dnf'
  'opensuse opensuse customize root zypper'
  'archlinux archlinux customize root pacman'
  'gentoo gentoo customize root emerge'
  'repair-alpine alpine repair root apk'
  'repair-debian debian repair root apt-get'
  'alpine-retry alpine customize root apk 1'
  'debian-retry debian customize root apt-get 1'
  'ubuntu-retry ubuntu customize root apt-get 1'
  'debian-custom debian customize root apt-get custom custom.example.org'
)
variants=(root empty unset invalid symlink blocked)

for spec in "${cases[@]}"; do
  read -r name os mode _ consumer failfirst prompt_answer <<< "$spec"
  failfirst=${failfirst:-0}
  retry_variants=("${variants[@]}")
  [[ "$failfirst" == 0 ]] || retry_variants=(root)
  for variant in "${retry_variants[@]}"; do
    c="$work/$name-$variant"
    label="$name/$variant"
    ctbin="$c/ctbin"
    mkdir -p "$c/etc/apt" "$c/etc/apk" "$c/var/lib/apt/lists" "$c/root" "$ctbin" "$c/creator-parent"
    printf '%s\n' "$failfirst" > "$c/failfirst"
    printf 'ID=%s\n' "$os" > "$c/etc/os-release"
    printf 'deb http://original.example.invalid/debian bookworm main\n' > "$c/etc/apt/sources.list"
    : > "$c/events"
    : > "$c/pcts"
    # Consumer shim: records the TMPDIR it sees and behaves like a package script that needs scratch space.
    cat > "$c/consumer" << 'SHIM'
#!/bin/sh
name=${0##*/}
seen=unset
[ "${TMPDIR+x}" ] && seen=$TMPDIR
exists=no
{ [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; } && exists=yes
printf '%s|TMPDIR=%s|exists=%s\n' "$name" "$seen" "$exists" >> "$CASE_ROOT/events"
if [ -n "${TMPDIR:-}" ]; then
  f=$(mktemp "$TMPDIR/pkg.XXXXXX") || { echo "mktemp failed" >&2; exit 100; }
  rm -f "$f"
fi
# Simulated native failure for the first K attempts (apk calls, apt-get update calls).
case "$name:${1:-}" in
  apt-get:update | apk:*)
    n=$(($(cat "$CASE_ROOT/n-$name" 2> /dev/null || echo 0) + 1))
    echo "$n" > "$CASE_ROOT/n-$name"
    ff=$(cat "$CASE_ROOT/failfirst")
    if [ "$ff" = custom ]; then
      host=$(sed -n 's|^deb http[s]*://\([^/]*\)/.*|\1|p' "$CASE_ROOT/etc/apt/sources.list" | head -n 1)
      if [ "$host" != custom.example.org ]; then
        echo "E: simulated failure" >&2
        exit 100
      fi
    elif [ "$n" -le "$ff" ]; then
      echo "E: simulated failure" >&2
      exit 100
    fi
    ;;
esac
exit 0
SHIM
    chmod +x "$c/consumer"
    ash=
    if [[ "$os" == alpine ]]; then
      if [[ -n "${ALPINE_BUSYBOX:-}" ]]; then
        ash="$ALPINE_BUSYBOX"
        tools=(ash sh test mkdir mktemp rm cat sed ls cp mv chmod stat awk grep head cut tr xargs shuf)
        for t in "${tools[@]}"; do ln -s "$ALPINE_BUSYBOX" "$ctbin/$t"; done
      else
        tools=(sh test mkdir mktemp rm cat sed ls cp mv chmod stat awk grep head cut tr xargs shuf)
        for t in "${tools[@]}"; do ln -s "$(command -v "$t")" "$ctbin/$t"; done
        ln -s "$(command -v sh)" "$ctbin/ash"
      fi
    else
      tools=(bash sh test mkdir mktemp rm cat sed ls cp mv chmod stat awk grep head cut tr xargs ln shuf)
      for t in "${tools[@]}"; do ln -s "$(command -v "$t")" "$ctbin/$t"; done
    fi
    for t in apk apt-get dnf yum zypper pacman emerge dpkg locale-gen wget; do ln -s ../consumer "$ctbin/$t"; done
    # Mirror reachability probes must not touch the network.
    printf '#!/bin/sh\nexit 0\n' > "$ctbin/timeout"
    chmod +x "$ctbin/timeout"
    printf '#!/bin/sh\nexit 0\n' > "$ctbin/getent"
    chmod +x "$ctbin/getent"
    # Region texts come from the actual owner; system paths are redirected into the case root.
    {
      if [[ "$mode" == repair ]]; then
        printf 'run_repair() {\n'
        awk '
          /^            # Package manager in-place repair: fix broken state and re-run install script/ { started = 1 }
          started { print }
          started && /APT\/DPKG state repaired in container/ { want_fi = 1; next }
          started && want_fi && /^            fi$/ { exit }
        ' "$BF"
        printf '}\n'
      else
        printf 'run_customize() {\n'
        awk '/^  msg_info "Customizing LXC Container"/,/^  msg_ok "Customized LXC Container"/' "$BF"
        printf '}\n'
      fi
    } | sed -e "s|/etc/|$c/etc/|g" -e "s|/var/lib/apt/|$c/var/lib/apt/|g" -e "s|/usr/share/zoneinfo|$c/zoneinfo|g" -e 's|< /dev/tty|< "$PROMPT_FILE"|g' > "$c/region.sh"
    grep -q 'run_' "$c/region.sh" && [[ $(wc -l < "$c/region.sh") -gt 6 ]] || {
      printf 'FAIL %s: actual region was not extracted\n' "$label" >&2
      exit 1
    }
    if sed -e "s|$c/etc/||g" -e "s|$c/var/lib/apt/||g" -e "s|$c/zoneinfo||g" "$c/region.sh" | grep -En '(^|[ "=:(])/(etc|var/lib/apt)/|< /dev/tty' >&2; then
      printf 'FAIL %s: unredirected system path in extracted region\n' "$label" >&2
      exit 1
    fi
    printf '%s\n' "${prompt_answer:-skip}" > "$c/prompt"
    receiver="$c/recv dir;\$x/leaf name"
    has_root=yes
    expect_rc=0
    expect_tmp="$receiver"
    case "$variant" in
      empty)
        has_root=empty
        expect_tmp='unset'
        ;;
      unset)
        has_root=no
        expect_tmp='unset'
        ;;
      invalid)
        receiver=relative/path
        expect_rc=65
        ;;
      symlink)
        mkdir -p "$c/realdir"
        ln -s "$c/realdir" "$c/alias"
        receiver="$c/alias/leaf"
        expect_rc=65
        ;;
      blocked)
        : > "$c/blocker"
        receiver="$c/blocker/leaf"
        expect_rc=1
        ;;
    esac
    case "$os" in alpine) family=alpine ;; *) family=other ;; esac
    rc=0
    env -i PATH="$PATH" HOME="$c/root" TMPDIR="$c/creator-only" CASE_ROOT="$c" OWNER_ROOT="$OWNER_ROOT" CTBIN="$ctbin" ASH="$ash" \
      MODE="$mode" HAS_ROOT="$has_root" RECEIVER="$receiver" var_os="$os" PROMPT_FILE="$c/prompt" FAMILY="$family" \
      timeout 60s bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?
    # The creator's variable was set to a path that exists only on the creator side.
    pcts=$(wc -l < "$c/pcts")
    events=$(wc -l < "$c/events")
    bad_events=$(grep -v '^prompt$' "$c/events" | grep -c -v "|TMPDIR=$expect_tmp|exists=yes$" || true)
    [[ "$expect_tmp" != unset ]] || bad_events=$(grep -v '^prompt$' "$c/events" | grep -c -v '|TMPDIR=unset|exists=no$' || true)
    check "$rc" "$expect_rc" "$label returns the actual preparation or customization status"
    [[ "$rc" == "$expect_rc" ]] || tail -n 5 "$c/output" >&2
    check "$(cat "$c/creator-after")" "CREATOR_TMPDIR_AFTER=$c/creator-only" "$label creator TMPDIR is unchanged"
    case "$variant" in
      root | empty | unset)
        check "$([[ $(grep -c "^$consumer|" "$c/events" || true) -ge 1 ]] && printf yes || printf no)" yes "$label the $consumer package consumer ran"
        check "$bad_events" 0 "$label every package consumer sees the selected receiving context"
        if [[ "$failfirst" != 0 ]]; then
          need=$failfirst
          [[ "$failfirst" != custom ]] || need=1
          check "$([[ $(grep -c "^$consumer|" "$c/events" || true) -gt "$need" ]] && printf yes || printf no)" yes "$label the first $failfirst $consumer attempt(s) failed and a mirror retry consumer ran"
          check "$(count '^prompt$' "$c/events")" "$([[ -n "${prompt_answer:-}" ]] && printf 1 || printf 0)" "$label mirror prompt count"
        fi
        ;;
      *)
        check "$events" 0 "$label no package or mirror command after context failure"
        check "$(count 'alternate mirrors' "$c/output")" 0 "$label context failure is not a mirror failure"
        ;;
    esac
    case "$variant" in
      root)
        check "$(stat -c %a "$receiver")" 1777 "$label explicit root leaf is shared and sticky"
        check "$(stat -c %a "$c/recv dir;\$x")" 755 "$label new intermediate parent is 0755"
        ;;
      invalid) check "$pcts" 0 "$label invalid override is rejected before any container command" ;;
      symlink) check "$(test -e "$c/realdir/leaf" && printf created || printf absent)" absent "$label symlink prefix is rejected before creation" ;;
    esac
  done
done

# Adapter fidelity: argv/positionals, stdin, stdout/stderr and exact status pass through the actual owner.
if declare -F _receiving_exec > /dev/null 2>&1 || grep -q '_receiving_exec' "$OWNER_ROOT/misc/bundle.func"; then
  c="$work/fidelity"
  mkdir -p "$c"
  : > "$c/pcts"
  rc=0
  env -i PATH="$PATH" HOME="$c" TMPDIR="$c/creator-only" CASE_ROOT="$c" OWNER_ROOT="$OWNER_ROOT" bash -c '
    source "$OWNER_ROOT/misc/bundle.func"
    pct() { shift 3; env PATH="$PATH" "$@"; }
    CTID=1
    export var_lxc_tmpdir="$CASE_ROOT/receiver root"
    _prepare_receiving_context || exit $?
    printf "stdin bytes\nline two" | _receiving_exec bash -c '"'"'cat; printf "%s|%s|%s|%s" "$0" "$1" "$2" "${TMPDIR-unset}" >&2; exit 37'"'"' arg\ zero "arg one" "a;b\$c"
  ' > "$c/out" 2> "$c/err" || rc=$?
  check "$rc" 37 'adapter preserves the exact child status'
  check "$(cat "$c/out")" "$(printf 'stdin bytes\nline two')" 'adapter leaves stdin untouched'
  check "$(cat "$c/err")" "arg zero|arg one|a;b\$c|$c/receiver root" 'adapter preserves shell -c positionals and selects the receiving root'
else
  check no yes 'actual adapter owner exists'
fi
printf '%s failure(s); actual customization/repair regions and receiving-context owner; pct/CT/package managers modeled\n' "$failures"
[[ "$failures" == 0 ]]

printf 'RUNTIME_HOOKS_RESULT failures=0\n'
