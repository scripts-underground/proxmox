#!/usr/bin/env bash
# Actual creator fragment, package helpers and cold update runner. Package/network
# commands and system paths are models; native CT proof is a separate gate.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  source "$CASE_ROOT/core.func"
  load_functions
  msg_info() { :; }
  msg_ok() { :; }
  msg_custom() { :; }
  msg_warn() { printf '%s\n' "$*" >&2; }
  msg_error() { printf '%s\n' "$*" >&2; }
  sleep() { :; }
  export PATH="$CASE_ROOT/bin:$PATH"
  source "$CASE_ROOT/owner.sh"
  case "$OWNER" in
    base)
      # shellcheck disable=SC2034 # Consumed by the extracted creator owner.
      CTID=3201 var_os=alpine
      _receiving_exec() { "$@"; }
      run_base
      ;;
    pkg)
      # shellcheck disable=SC2034 # Consumed by the sourced package owner.
      PKG_MANAGER=apk
      pkg_update
      ;;
    upgrade)
      # shellcheck disable=SC2034 # Consumed by the sourced package owner.
      PKG_MANAGER=apk
      pkg_upgrade
      ;;
    runner)
      # shellcheck disable=SC2034 # Consumed by the sourced update runner.
      NSAPP=alpine APP=Alpine
      # Lock admission is modeled here; its native serialization has its own suite.
      app_maintenance_begin() { :; }
      check_container_resources() { :; }
      update_script() { apk -U upgrade; }
      run_update_script
      ;;
  esac
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
OWNER_ROOT=$(realpath -e "${ALPINE_REPOSITORY_OWNER_ROOT:-$ROOT}")
work=$(mktemp -d "$TMPDIR/alpine-repositories.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for owner in base pkg upgrade runner; do
  for scenario in pinned fallback legacy legacy-fallback advanced tagged-mixed edge disabled non-alpine alternate-edge alternate-fallback typed-fallback ndx-fallback trailing-fallback etc-edge lib-edge masked masked-edge ignored-list variable-edge component-edge variable-fallback literal-dollar-fallback mixed-fallback dot-url-edge dot-component-edge dot-encoded-edge undefined-edge leading-space-edge; do
    [[ "$owner" != base || "$scenario" != non-alpine ]] || continue
    c="$work/$owner-$scenario"
    mkdir -p "$c"/{bin,etc/apk/repositories.d,lib/apk/repositories.d,home,tmp,var/lib/scripts-underground/update-pending}
    printf 'ID=alpine\nVERSION_ID=3.23.8\n' > "$c/etc/os-release"
    branch=v3.23
    case "$scenario" in
      legacy*) branch=latest-stable ;;
      advanced) branch=v3.24 ;;
      edge) branch=edge ;;
      non-alpine) printf 'ID=debian\nVERSION_ID=13\n' > "$c/etc/os-release" ;;
    esac
    printf '# operator comment\nhttps://original.invalid/alpine/%s/main\n@testing https://original.invalid/alpine/%s/community # retained\nhttps://vendor.invalid/custom/packages\n' "$branch" "$branch" > "$c/etc/apk/repositories"
    case "$scenario" in
      tagged-mixed) printf '@experimental https://other.invalid/alpine/v3.24/community\n' >> "$c/etc/apk/repositories" ;;
      disabled) printf '# https://other.invalid/alpine/latest-stable/community\n' >> "$c/etc/apk/repositories" ;;
      alternate-edge) printf 'https://other.invalid/pub/mirrors/alpine/edge/main\n' >> "$c/etc/apk/repositories" ;;
      alternate-fallback) sed -i 's|/alpine/|/pub/alpine/|g' "$c/etc/apk/repositories" ;;
      typed-fallback) sed -i '2s/^/v2 /;3s/^/v3 /' "$c/etc/apk/repositories" ;;
      ndx-fallback) sed -i '2s/^/ndx /;3s/^/ndx /' "$c/etc/apk/repositories" ;;
      trailing-fallback) sed -i 's|/main$|/main/|;s|/community #|/community/ #|' "$c/etc/apk/repositories" ;;
      etc-edge | masked-edge) printf 'https://other.invalid/alpine/edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      lib-edge) printf 'https://other.invalid/alpine/edge/main\n' > "$c/lib/apk/repositories.d/operator.list" ;;
      masked)
        : > "$c/etc/apk/repositories.d/operator.list"
        printf 'https://other.invalid/alpine/edge/main\n' > "$c/lib/apk/repositories.d/operator.list"
        ;;
      ignored-list)
        printf 'https://other.invalid/alpine/edge/main\n' > "$c/etc/apk/repositories.d/operator.txt"
        printf 'https://other.invalid/alpine/edge/main\n' > "$c/etc/apk/repositories.d/.hidden.list"
        ;;
      variable-edge | variable-fallback)
        printf 'set release=%s\n' "$([[ "$scenario" == variable-edge ]] && echo edge || echo v3.23)" > "$c/lib/apk/repositories.d/00-vars.list"
        printf 'set -default release=edge\nset root=https://original.invalid/pub/alpine\nv2 @operator ${root}/${release} main community # retained\nhttps://vendor.invalid/custom/packages\n' > "$c/etc/apk/repositories.d/10-operator.list"
        ;;
      component-edge) printf 'v2 https://other.invalid/pub/alpine edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      literal-dollar-fallback)
        printf 'set key=main\nset -default -default key=${key}\nv2 @p$ss https://original.invalid/pub/alpine/v3.23 ${key} p$ss # retained\nhttps://vendor.invalid/p$ss\n' > "$c/etc/apk/repositories.d/operator.list"
        ;;
      mixed-fallback) printf 'v2 https://original.invalid alpine/v3.23/main vendor/custom\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      dot-url-edge) printf 'https://other.invalid/alpine/v3.23/../edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      dot-component-edge) printf 'v2 https://other.invalid/alpine/v3.23 ../edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      dot-encoded-edge) printf 'set component=%%2e%%2e/edge/main\nv3 https://other.invalid/alpine/v3.23 ${component}\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      undefined-edge) printf 'v2 ${missing}/alpine/edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
      leading-space-edge) printf '  # silently aborts native file\nhttps://other.invalid/alpine/edge/main\n' > "$c/etc/apk/repositories.d/operator.list" ;;
    esac
    [[ "$scenario" != masked-edge ]] || printf 'https://other.invalid/alpine/v3.23/main\n' > "$c/lib/apk/repositories.d/operator.list"
    cp "$c/etc/apk/repositories" "$c/before"
    if [[ "$scenario" == variable-fallback ]]; then
      cp "$c/etc/apk/repositories.d/10-operator.list" "$c/operator-before"
    elif [[ "$scenario" == literal-dollar-fallback || "$scenario" == mixed-fallback ]]; then
      cp "$c/etc/apk/repositories.d/operator.list" "$c/operator-before"
    fi
    if [[ "$owner" == runner ]]; then
      printf 'prior pending bytes\n' > "$c/var/lib/scripts-underground/update-pending/alpine"
    fi
    : > "$c/events"
    cat > "$c/bin/apk" << 'SHIM'
#!/bin/sh
printf 'apk %s\n' "$*" >> "$CASE_ROOT/events"
cat "$CASE_ROOT/etc/apk/repositories" >> "$CASE_ROOT/seen"
case "$OWNER:$SCENARIO" in
  base:*fallback | pkg:*fallback)
    n=$(grep -c '^apk ' "$CASE_ROOT/events")
    [ "$n" != 1 ] || exit 4
    ;;
esac
exit 0
SHIM
    printf '#!/bin/sh\nexit 0\n' > "$c/bin/wget"
    cp "$c/bin/wget" "$c/bin/timeout"
    if [[ -n "${ALPINE_BUSYBOX:-}" ]]; then
      for tool in ash awk sed sort cmp cp mv; do ln -s "$ALPINE_BUSYBOX" "$c/bin/$tool"; done
    else
      ln -s /bin/sh "$c/bin/ash"
    fi
    chmod +x "$c/bin/"{apk,wget,timeout}
    redirect() { sed -e "s|/var/lib/scripts-underground|$c/var/lib/scripts-underground|g" -e "s|/lib/apk/|$c/lib/apk/|g" -e "s|/etc/|$c/etc/|g"; }
    redirect < "$OWNER_ROOT/misc/core.func" > "$c/core.func"
    case "$owner" in
      base)
        {
          sed -n '/^_alpine_base_packages() {/,/^}/p' "$OWNER_ROOT/misc/build.func"
          printf 'run_base() {\n'
          awk '/^  if \[ "\$var_os" == "alpine" \]; then$/ { found=1; next }
            found && /^  elif / { exit } found { print }' "$OWNER_ROOT/misc/build.func"
          printf '}\n'
        } | redirect > "$c/owner.sh"
        ;;
      pkg | upgrade)
        sed -n "/^pkg_${owner/pkg/update}() {/,/^}/p" "$OWNER_ROOT/misc/install.func" | redirect > "$c/owner.sh"
        ;;
      runner) : > "$c/owner.sh" ;;
    esac
    rc=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$c/tmp" CASE_ROOT="$c" OWNER="$owner" SCENARIO="$scenario" \
      BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/error.log" VERBOSE=yes \
      timeout 30 bash "$0" --child > "$c/output" 2>&1 || rc=$?
    label="$owner/$scenario"
    expected_status=0
    if [[ "$scenario" == *-edge && "$scenario" != alternate-edge || "$scenario" == alternate-edge && "$owner" != base ]]; then
      check "$rc" 65 "$label rejects every effective native source"
      check "$(wc -l < "$c/events")" 0 "$label no package or hook effect"
      if [[ "$owner" == runner ]]; then
        check "$(cat "$c/var/lib/scripts-underground/update-pending/alpine")" 'prior pending bytes' "$label refusal preserves pending state"
      fi
    elif [[ ("$owner" == base || "$owner" == pkg) && ("$scenario" == variable-fallback || "$scenario" == literal-dollar-fallback || "$scenario" == mixed-fallback) ]]; then
      expected_status=65
      [[ "$owner" != base ]] || expected_status=1
      check "$rc" "$expected_status" "$label mirror refuses without claiming success"
      check "$(wc -l < "$c/events")" 1 "$label refused mirror never reaches another package effect"
      operator_file="$c/etc/apk/repositories.d/operator.list"
      [[ "$scenario" != variable-fallback ]] || operator_file="$c/etc/apk/repositories.d/10-operator.list"
      check "$(cmp -s "$c/operator-before" "$operator_file" && echo unchanged || echo changed)" unchanged "$label declaration bytes retained"
      check "$(grep -c "Cannot mirror $operator_file:" "$c/output" || true)" 1 "$label names refused file and line"
      if [[ "$owner" == pkg ]]; then
        check "$(cmp -s "$c/before" "$c/etc/apk/repositories" && echo unchanged || echo changed)" unchanged "$label refusal before any file publication"
      fi
    elif [[ "$owner" == base ]]; then
      check "$rc" 0 "$label creator completes"
      check "$(grep -c '/alpine/v3.23/' "$c/etc/apk/repositories" || true)" 2 "$label actual template branch pinned"
      check "$(grep -c latest-stable "$c/seen" 2> /dev/null || true)" 0 "$label package consumer never sees moving alias"
    elif [[ "$scenario" == legacy* || "$scenario" == advanced || "$scenario" == tagged-mixed || "$scenario" == edge ]]; then
      check "$rc" 65 "$label refuses implicit release selection"
      check "$(wc -l < "$c/events")" 0 "$label no package or hook effect"
      check "$(cmp -s "$c/before" "$c/etc/apk/repositories" && echo unchanged || echo changed)" unchanged "$label source bytes preserved"
      check "$(grep -c 'installed branch v3.23' "$c/output" || true)" 1 "$label current state reported"
      if [[ "$owner" == runner ]]; then
        check "$(cat "$c/var/lib/scripts-underground/update-pending/alpine")" 'prior pending bytes' "$label refusal preserves pending state"
      fi
    else
      check "$rc" 0 "$label ordinary update succeeds"
      check "$(grep -c '/alpine/v3.23/' "$c/etc/apk/repositories" || true)" 2 "$label branch retained"
      check "$(grep -c '^# operator comment\|# retained\|https://vendor.invalid/custom/packages' "$c/etc/apk/repositories" || true)" 3 "$label unrelated/comment/tag bytes retained"
    fi
    [[ "$rc" == 0 || "$rc" == 65 || "$rc" == "${expected_status:-}" ]] || tail -n 8 "$c/output" >&2
    if [[ "$owner" == pkg && "$scenario" == *fallback && "$scenario" != legacy-fallback && "$scenario" != variable-fallback && "$scenario" != literal-dollar-fallback && "$scenario" != mixed-fallback ]]; then
      check "$(grep -c original.invalid "$c/etc/apk/repositories" || true)" 0 "$label mirror transport changed"
      check "$(grep -c '@testing https://' "$c/etc/apk/repositories" || true)" 1 "$label scheme and tag retained"
      mirror_url=$(grep -o 'https://[^/]*' "$c/etc/apk/repositories" | head -n 1)
      sed "s|https://original.invalid|$mirror_url|g" "$c/before" > "$c/expected"
      check "$(cmp -s "$c/expected" "$c/etc/apk/repositories" && echo preserved || echo changed)" preserved "$label only host changed"
    fi
  done
done
# A failed publication must keep the previous configuration, like sed -i did.
c="$work/publication-failure"
mkdir -p "$c/etc/apk"
printf 'ID=alpine\nVERSION_ID=3.23.8\n' > "$c/etc/os-release"
printf 'https://original.invalid/alpine/v3.23/main\n' > "$c/etc/apk/repositories"
cp "$c/etc/apk/repositories" "$c/before"
sed -e "s|/lib/apk/|$c/lib/apk/|g" -e "s|/etc/|$c/etc/|g" "$OWNER_ROOT/misc/core.func" > "$c/core.func"
rc=0
bash -c 'source "$1"; mv() { return 73; }; _alpine_repository_policy mirror new.invalid' _ "$c/core.func" > "$c/output" 2>&1 || rc=$?
check "$rc" 73 'mirror publication failure preserves native status'
check "$(cmp -s "$c/before" "$c/etc/apk/repositories" && echo unchanged || echo changed)" unchanged 'mirror publication failure preserves prior repository bytes'
for fault in empty truncated early-receipt; do
  c="$work/writer-$fault"
  mkdir -p "$c/etc/apk"
  printf 'ID=alpine\nVERSION_ID=3.23.8\n' > "$c/etc/os-release"
  printf 'https://original.invalid/alpine/v3.23/main\nhttps://original.invalid/alpine/v3.23/community\n' > "$c/etc/apk/repositories"
  cp "$c/etc/apk/repositories" "$c/before"
  sed -e "s|/lib/apk/|$c/lib/apk/|g" -e "s|/etc/|$c/etc/|g" "$OWNER_ROOT/misc/core.func" > "$c/core.func"
  rc=0
  WRITER_FAULT="$fault" bash -c '
    source "$1"
    awk() {
      if [[ -n "${_ar_stage:-}" ]]; then
        if [[ "$WRITER_FAULT" != empty ]]; then printf "truncated\n" > "$_ar_stage"; fi
        [[ "$WRITER_FAULT" != early-receipt ]] || printf "complete:1\n"
        return 0
      fi
      command awk "$@"
    }
    _alpine_repository_policy mirror new.invalid
  ' _ "$c/core.func" > "$c/output" 2>&1 || rc=$?
  check "$rc" 65 "$fault writer success without complete receipt refuses"
  check "$(cmp -s "$c/before" "$c/etc/apk/repositories" && echo unchanged || echo changed)" unchanged "$fault writer never publishes truncated bytes"
done
printf '%s failure(s); actual Alpine repository owners with explicit package/transport models\n' "$failures"
[[ "$failures" == 0 ]]
printf 'RUNTIME_HOOKS_RESULT failures=0\n'
