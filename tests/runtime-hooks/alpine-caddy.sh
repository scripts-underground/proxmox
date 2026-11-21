#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
script_type=lxc app=alpine-caddy
variants=(fresh fresh-no fresh-amd64 fresh-arm64 fresh-low-memory fresh-low-limit fresh-low-disk fresh-unknown-memory fresh-unknown-disk update update-addon update-low-memory update-low-limit update-low-disk update-unknown-memory update-unknown-disk package restart missing build)
hook_paths=(/var/www www /proc/meminfo meminfo /sys/fs/cgroup cgroup)
runtime_hooks_variant() {
  case "$variant" in
    fresh*) role=install ;;
    package | restart | build) fault=$variant ;;
  esac
}
runtime_hooks_model() {
  TAB3=''
  apk() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$APP_FAULT" != package ]] || return 42
  }
  rc-update() { printf 'enable %s\n' "$*" >> "$c/services"; }
  service() { printf '%s %s\n' "$2" "$1" >> "$c/services"; }
  rc-service() {
    [[ "$APP_FAULT" != restart ]] || return 43
    printf '%s %s\n' "$2" "$1" >> "$c/services"
  }
  setup_go() { printf 'go setup\n' >> "$c/addon"; }
  df() {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf 'fixture 16777216 1024 %s 1%% /opt\n' "$(cat "$c/disk")"
  }
  uname() {
    if [[ "$1" == -m ]]; then cat "$c/arch"; else command uname "$@"; fi
  }
  curl() {
    case "${!#}" in
      *go.dev*) printf 'go1.26.0\n' ;;
      *api.github.com*) printf '{"tag_name": "v0.4.5"}\n' ;;
      *)
        local url=$2 output=${!#} arch
        arch=$(cat "$c/arch")
        [[ "$arch" != x86_64 ]] || arch=amd64
        [[ "$arch" != aarch64 ]] || arch=arm64
        printf '%s\n' "$url" >> "$c/assets"
        [[ "$url" == *"xcaddy_0.4.5_linux_${arch}.tar.gz" ]] || return 44
        tar czf "$output" -C "$c/payload" xcaddy
        ;;
    esac
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/etc/caddy" "$c/www/html" "$c/payload" "$c/cgroup"
  printf 'operator Caddy configuration\n' > "$c/etc/caddy/Caddyfile"
  printf 'operator HTTP content\n' > "$c/www/html/saved.txt"
  : > "$c/packages"
  : > "$c/assets"
  : > "$c/addon"
  printf 'x86_64\n' > "$c/arch"
  printf 'MemAvailable: 16777216 kB\n' > "$c/meminfo"
  printf 'max\n' > "$c/cgroup/memory.max"
  printf '16777216\n' > "$c/disk"
  printf 'existing xCaddy-built executable\n' > "$c/opt/caddy"
  case "$variant" in
    fresh-no) printf 'n\n' > "$c/stdin" ;;
    fresh-*) printf 'yes\n' > "$c/stdin" ;;
    missing)
      rm "$c/etc/caddy/Caddyfile"
      rmdir "$c/etc/caddy"
      ;;
  esac
  case "$variant" in
    *-low-memory) printf 'MemAvailable: 131072 kB\n' > "$c/meminfo" ;;
    *-low-limit) printf '134217728\n' > "$c/cgroup/memory.max" ;;
    *-low-disk) printf '1048576\n' > "$c/disk" ;;
    *-unknown-memory) printf 'unknown\n' > "$c/meminfo" ;;
    *-unknown-disk) printf 'unknown\n' > "$c/disk" ;;
  esac
  [[ "$variant" != fresh-arm64 ]] || printf 'aarch64\n' > "$c/arch"
  printf 'unrelated operator bytes\n' > "$c/opt/xcaddy-operator.txt"
  cat > "$c/payload/xcaddy" << 'SH'
#!/usr/bin/env bash
printf 'xcaddy %s\n' "$*" >> "$APP_FIXTURE/addon"
[[ "$APP_FAULT" != build ]] || exit 52
[[ "$1" == build && "$2" == --output ]] || exit 53
printf 'new native build\n' > "$3"
SH
  chmod 0755 "$c/payload/xcaddy"
  case "$variant" in
    update-* | build) cp "$c/payload/xcaddy" "$c/local/bin/xcaddy" ;;
  esac
}
runtime_hooks_expected() {
  case "$fault" in package) expected=42 ;; restart) expected=43 ;; build) expected=52 ;; esac
  [[ "$variant" != missing ]] || expected=1
  case "$variant" in update-*-memory | update-*-limit | update-*-disk) expected=1 ;; esac
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/xcaddy-operator.txt" 2> /dev/null || true)" 'unrelated operator bytes' "$app/$variant unrelated addon-named file retained"
  check "$(cat "$c/www/html/saved.txt")" 'operator HTTP content' "$app/$variant HTTP content retained"
  if [[ "$role" == install ]]; then
    check "$(grep -c '^start caddy$' "$c/services" || true)" 1 "$app/$variant starts Caddy after optional prompt"
    check "$(grep -c '^enable add caddy default$' "$c/services" || true)" 1 "$app/$variant enables Caddy"
    case "$variant" in
      fresh | fresh-no) check "$(wc -c < "$c/addon")" 0 "$app/$variant addon remains opt-in" ;;
      fresh-amd64 | fresh-arm64)
        check "$(grep -c '^xcaddy build --output /opt/.xcaddy-build\.' "$c/addon" || true)" 1 "$app/$variant selected addon runs staged build"
        ;;
    esac
  elif [[ "$variant" != missing ]]; then
    check "$(cat "$c/etc/caddy/Caddyfile")" 'operator Caddy configuration' "$app/$variant configuration retained"
  else
    check "$(wc -c < "$c/packages")" 0 "$app missing installation has no package effects"
  fi
  case "$variant" in
    fresh-amd64 | fresh-arm64 | update-addon)
      check "$(cat "$c/opt/caddy")" 'new native build' "$app/$variant publishes completed optional binary"
      check "$(test -e "$c/root/.xcaddy-requested" && echo present || echo absent)" absent "$app/$variant clears successful request"
      ;;
    *) check "$(cat "$c/opt/caddy")" 'existing xCaddy-built executable' "$app/$variant existing built binary retained" ;;
  esac
  case "$variant" in
    *-low-memory | *-low-limit | *-low-disk | *-unknown-memory | *-unknown-disk)
      check "$(wc -c < "$c/addon")" 0 "$app/$variant refusal has no Go or build effects"
      check "$(wc -c < "$c/assets")" 0 "$app/$variant refusal downloads no xCaddy"
      check "$(grep -q 'xCaddy requires' "$c/output" && echo present || echo absent)" present "$app/$variant reports required sizes"
      check "$(grep -q 'Proxmox Resources' "$c/output" && echo present || echo absent)" present "$app/$variant explains resource change and retry"
      if [[ "$role" == install ]]; then
        check "$(test -e "$c/root/.xcaddy-requested" && echo present || echo absent)" present "$app/$variant retains opt-in for update retry"
      else
        check "$(wc -c < "$c/packages")" 0 "$app/$variant refusal precedes update package effects"
        check "$(wc -c < "$c/services")" 0 "$app/$variant refusal leaves running service alone"
      fi
      ;;
  esac
}
runtime_hooks_retry_needed() { [[ "$fault" == package || "$fault" == restart || "$fault" == build ]]; }
runtime_hooks_main "$@"
