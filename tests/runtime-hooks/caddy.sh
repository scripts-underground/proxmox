#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold install/update bundles with real release, pending and prompt owners.
# APT, repository setup, Go and xcaddy builds are modeled external effects.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=caddy
script_type=lxc
release_app=xcaddy release_mode=binary release_asset=xcaddy_2.0.0_linux_amd64.deb
variants=(fresh fresh-xcaddy fresh-low-cgroup fresh-low-memtotal update pending package checker no-update selected missing low-cgroup low-memtotal)
hook_paths=(/proc/meminfo meminfo /sys/fs/cgroup/memory.max memory.max)
runtime_hooks_variant() {
  case "$variant" in
    fresh | fresh-xcaddy | fresh-low-*) role=install ;;
    package) fault=package ;;
    checker) fault=checker ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  setup_deb822_repo() { printf 'repo %s\n' "$*" >> "$c/packages"; }
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$1" != upgrade || "$APP_FAULT" != package ]] || return 53
    # APT leaves an installed package alone unless asked to install or reinstall it.
    if [[ " $* " == *' caddy '* ]]; then
      printf 'caddy package\n' > "$c/caddy-consumer"
      mkdir -p "$c/etc/caddy"
      [[ -f "$c/etc/caddy/Caddyfile" ]] || printf ':80 {\n  respond "saved site"\n}\n' > "$c/etc/caddy/Caddyfile"
    fi
  }
  _deploy_release_deb() {
    cat "$1" > "$c/package-consumer"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/xcaddy-builds"\n' "$c" > "$c/local/bin/xcaddy"
    chmod 0755 "$c/local/bin/xcaddy"
  }
}
addon_release_setup() {
  : > "$c/packages"
  : > "$c/xcaddy-builds"
  printf 'MemTotal: 2097152 kB\n' > "$c/meminfo"
  printf 'max\n' > "$c/memory.max"
  case "$variant" in
    fresh-xcaddy) printf '1610612736\n' > "$c/memory.max" ;;
    selected) printf 'MemTotal: 1572864 kB\n' > "$c/meminfo" ;;
    *low-cgroup) printf '536870912\n' > "$c/memory.max" ;;
    *low-memtotal)
      printf 'MemTotal: 1571840 kB\n' > "$c/meminfo"
      printf '2147483648\n' > "$c/memory.max"
      ;;
  esac
  case "$variant" in fresh-xcaddy | fresh-low-*) printf 'y\n' > "$c/stdin" ;; esac
  if [[ "$role" == update ]]; then
    [[ "$variant" != missing ]] || return 0
    mkdir -p "$c/etc/caddy"
    printf ':80 {\n  respond "saved site"\n}\n' > "$c/etc/caddy/Caddyfile"
    printf 'caddy package\n' > "$c/caddy-consumer"
    case "$variant" in
      checker | no-update | selected | low-*)
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/xcaddy-builds"\n' "$c" > "$c/local/bin/xcaddy"
        chmod 0755 "$c/local/bin/xcaddy"
        ;;
      *) rm -f "$c/home/.xcaddy" ;;
    esac
    if [[ "$variant" == pending ]]; then
      printf 'interrupted update\n' > "$c/state/caddy"
      rm "$c/caddy-consumer"
    fi
  fi
}
runtime_hooks_expected() {
  [[ "$variant" != missing ]] || expected=1
  case "$variant" in low-*) expected=1 ;; esac
  case "$fault" in checker) expected=17 ;; package) expected=53 ;; esac
}
runtime_hooks_assert() {
  local reinstalls
  reinstalls=$(grep -c -- '--reinstall caddy' "$c/packages" || true)
  if [[ "$role" == install ]]; then
    check "$(grep -c '^install -y caddy$' "$c/packages" || true)" 1 "$app/$mode/$variant installs the Caddy package"
    check "$(cat "$c/caddy-consumer" 2> /dev/null || true)" 'caddy package' "$app/$mode/$variant package consumer present"
    if [[ "$variant" == fresh-low-* ]]; then
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/$variant no xcaddy download below measured memory requirement"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/$variant refuses build below measured memory requirement"
      check "$(test -x "$c/local/bin/xcaddy" && printf installed || printf absent)" absent "$app/$mode/$variant does not install xcaddy"
      check "$(grep -Eq 'xCaddy.*at least [0-9]+ MiB' "$c/output" && printf present || true)" present "$app/$mode/$variant explains minimum RAM"
      check "$(grep -Eq 'Proxmox.*Memory.*rerun' "$c/output" && printf present || true)" present "$app/$mode/$variant explains memory and retry"
      check "$(test -f "$c/root/.xcaddy-requested" && printf requested || printf missing)" requested "$app/$mode/$variant retains opt-in for an updater retry"
      printf 'MemTotal: 2097152 kB\n' > "$c/meminfo"
      printf '2147483648\n' > "$c/memory.max"
    elif [[ "$variant" == fresh ]]; then
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/fresh EOF keeps the default No answer"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/fresh EOF builds nothing"
    else
      check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/$variant xcaddy package deployed"
      check "$(cat "$c/xcaddy-builds")" build "$app/$mode/$variant xcaddy build runs once"
    fi
    return
  fi
  runtime_hooks_configuration_assert
  if [[ "$variant" == missing ]]; then
    check "$(stat -c %s "$c/packages")" 0 "$app/$mode/missing refuses before package effects"
    check "$(stat -c %s "$c/requests")" 0 "$app/$mode/missing refuses before release effects"
    mkdir -p "$c/etc/caddy"
    printf ':80 {\n  respond "saved site"\n}\n' > "$c/etc/caddy/Caddyfile"
    return
  fi
  check "$(cat "$c/etc/caddy/Caddyfile")" "$(printf ':80 {\n  respond "saved site"\n}')" "$app/$mode/$variant Caddyfile retained"
  case "$variant" in
    update | no-update | selected | checker)
      check "$reinstalls" 0 "$app/$mode/$variant ordinary update does not reinstall Caddy"
      ;;
    pending)
      check "$reinstalls" 1 "$app/$mode/pending forced update reinstalls Caddy"
      check "$(cat "$c/caddy-consumer" 2> /dev/null || true)" 'caddy package' "$app/$mode/pending package consumer repaired"
      ;;
  esac
  case "$variant" in
    update | pending | package)
      check "$(stat -c %s "$c/requests")" 0 "$app/$mode/$variant no xcaddy lookup without xcaddy"
      ;;
    no-update | checker)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/$variant no xcaddy deployment"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/$variant no xcaddy build"
      ;;
    selected)
      check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/selected xcaddy consumer"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app/$mode/selected binds the selected raw tag"
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app/$mode/selected resolves latest once"
      check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$mode/selected never deploys moved latest"
      check "$(cat "$c/xcaddy-builds")" build "$app/$mode/selected xcaddy build runs once"
      ;;
    low-*)
      check "$(cat "$c/package-consumer")" 'old package' "$app/$mode/$variant keeps existing xcaddy package"
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/$variant refuses before xcaddy deployment"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/$variant refuses build"
      check "$(cat "$c/caddy-consumer")" 'caddy package' "$app/$mode/$variant retains plain Caddy"
      check "$(grep -Eq 'xCaddy.*at least [0-9]+ MiB' "$c/output" && printf present || true)" present "$app/$mode/$variant explains minimum RAM"
      check "$(grep -Eq 'Proxmox.*Memory.*rerun' "$c/output" && printf present || true)" present "$app/$mode/$variant explains memory and retry"
      # A second cold process sees the newly raised actual limit, not cached RAM.
      printf 'MemTotal: 2097152 kB\n' > "$c/meminfo"
      printf '2147483648\n' > "$c/memory.max"
      ;;
  esac
  if [[ "$variant" == package ]]; then
    check "$(grep -c '^upgrade -y$' "$c/packages" || true)" 1 "$app/$mode/package failure stops after the failed upgrade"
    check "$reinstalls" 0 "$app/$mode/package failure has no later package effects"
  fi
}
runtime_hooks_retry_needed() {
  [[ "$role" == update && "$expected" != 0 || "$variant" == fresh-low-* ]]
}
runtime_hooks_retry_assert() {
  if [[ "$variant" == fresh-low-* ]]; then
    check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/$variant updater installs requested xcaddy after RAM increase"
    check "$(cat "$c/xcaddy-builds")" build "$app/$mode/$variant updater builds once after RAM increase"
    check "$(test -f "$c/root/.xcaddy-requested" && printf present || printf absent)" absent "$app/$mode/$variant consumes successful opt-in intent"
    return
  fi
  check "$(grep -c -- '--reinstall caddy' "$c/packages" || true)" 1 "$app/$mode/$variant pending retry reinstalls Caddy"
  check "$(cat "$c/caddy-consumer")" 'caddy package' "$app/$mode/$variant retry package consumer"
  check "$(cat "$c/etc/caddy/Caddyfile")" "$(printf ':80 {\n  respond "saved site"\n}')" "$app/$mode/$variant retry retains Caddyfile"
  if [[ "$variant" == checker || "$variant" == low-* ]]; then
    check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/checker retry redeploys the selected xcaddy"
    check "$(cat "$c/xcaddy-builds")" build "$app/$mode/checker retry builds once"
  fi
}
runtime_hooks_main "$@"
