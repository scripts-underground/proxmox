#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Shared addon activation owner: real records/locks, native-init effects modeled.
# shellcheck disable=SC2034
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
source "$ROOT/tests/lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac

if [[ "${1:-}" == --child ]]; then
  c=$2 phase=$3
  source "$c/core.func"
  source "$c/addon_lxc.func"
  APP_SLUG=activation-fixture INIT_SYSTEM=systemd
  systemctl() {
    local action=$1 unit=${!#}
    [[ "$unit" == fixture.service ]] || return 4
    if [[ "$action" == show ]]; then
      [[ ! -f "$c/query-failure" ]] || return 23
      printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=enabled\n' "$(cat "$c/state")"
    elif [[ "$action" == start || "$action" == restart ]]; then
      printf '%s\n' "$action" >> "$c/starts"
      printf failed > "$c/state"
      [[ ! -f "$c/start-failure" ]] || return 47
      cat "$c/executable" > "$c/consumer"
      printf active > "$c/state"
    fi
  }
  ln() {
    [[ ! -f "$c/publication-failure" ]] || return 37
    command ln "$@"
  }
  app_maintenance_begin "$APP_SLUG"
  if [[ "$phase" == retire ]]; then
    addon_service_retire
    exit
  fi
  owed=0
  addon_service_begin fixture.service owed
  printf '%s\n' "$owed" > "$c/owed"
  [[ "$phase" != complete ]] || addon_service_complete fixture.service
  exit
fi

work=$(mktemp -d "$TMPDIR/addon-service-actions.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
invoke() {
  local status=0
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" bash "$0" --child "$c" "$1" > "$c/output-$1" 2>&1 || status=$?
  check "$status" "$2" "$variant/$1 exact status"
}
for variant in retry stopped pending-stopped auto-restart query publication unsafe-link unsafe-mode malformed wrong-unit; do
  c="$work/$variant"
  mkdir -p "$c/home" "$c/actions"
  chmod 0700 "$c/actions"
  sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
  sed "s|/var/lib/scripts-underground/addon-service-actions|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
  printf active > "$c/state"
  printf 'new consumer\n' > "$c/executable"
  : > "$c/starts"
  record="$c/actions/activation-fixture"
  case "$variant" in
    stopped | pending-stopped) printf inactive > "$c/state" ;;
    auto-restart) printf activating > "$c/state" ;;
    query) : > "$c/query-failure" ;;
    publication) : > "$c/publication-failure" ;;
    unsafe-link)
      printf 'operator file\n' > "$c/operator"
      ln -s "$c/operator" "$record"
      ;;
    unsafe-mode | malformed | wrong-unit)
      printf 'v1\nsystemd\nfixture.service\n' > "$record"
      chmod 0600 "$record"
      case "$variant" in
        unsafe-mode) chmod 0644 "$record" ;;
        malformed) printf 'v1\nsystemd\n' > "$record" ;;
        wrong-unit) printf 'v1\nsystemd\nforeign.service\n' > "$record" ;;
      esac
      ;;
  esac
  case "$variant" in
    query) invoke begin 23 ;;
    publication) invoke begin 37 ;;
    unsafe-link | unsafe-mode) invoke begin 69 ;;
    malformed | wrong-unit) invoke begin 65 ;;
    stopped | pending-stopped)
      # An unrelated pending marker cannot establish activation intent.
      [[ "$variant" != pending-stopped ]] || printf unfinished > "$c/pending"
      invoke complete 0
      check "$(cat "$c/owed")" 0 "$variant never invents an activation obligation"
      check "$(wc -l < "$c/starts")" 0 "$variant never starts an operator-stopped service"
      check "$(test -e "$record" && printf present || printf absent)" absent "$variant has no owed record"
      ;;
    auto-restart)
      invoke begin 0
      check "$(cat "$c/owed")" 1 'auto-restart is positive prior activation intent'
      invoke complete 0
      check "$(cat "$c/consumer")" 'new consumer' 'auto-restart reaches final consumer'
      ;;
    retry)
      invoke begin 0
      check "$(stat -c '%u:%a:%h' "$record")" 0:600:1 'owed activation is private checked data'
      printf inactive > "$c/state"
      : > "$c/start-failure"
      invoke complete 47
      check "$(test -f "$record" && printf present || printf absent)" present 'failed activation retains obligation'
      rm "$c/start-failure"
      invoke complete 0
      check "$(cat "$c/owed")" 1 'cold failed-state retry reads original obligation'
      check "$(cat "$c/consumer")" 'new consumer' 'cold failed-state retry reaches updated consumer'
      check "$(cat "$c/state")" active 'cold failed-state retry restores active service'
      check "$(test -e "$record" && printf present || printf absent)" absent 'verified activation retires obligation'
      ;;
  esac
  case "$variant" in
    query | publication | unsafe-* | malformed | wrong-unit)
      check "$(wc -l < "$c/starts")" 0 "$variant refuses before service effects"
      ;;
  esac
  [[ "$variant" != unsafe-link ]] || check "$(cat "$c/operator")" 'operator file' 'unsafe record never mutates its target'
  case "$variant" in
    retry | auto-restart | stopped | pending-stopped | query | publication)
      # A successful uninstall is independent of current native service state.
      printf 'v1\nsystemd\nfixture.service\n' > "$record"
      chmod 0600 "$record"
      invoke retire 0
      check "$(test -e "$record" && printf present || printf absent)" absent "$variant uninstall retires checked obligation"
      ;;
    unsafe-link | unsafe-mode) invoke retire 69 ;;
    malformed | wrong-unit)
      # A valid receipt for another native unit is still this app's teardown
      # state; malformed data is never deleted on the strength of a filename.
      if [[ "$variant" == malformed ]]; then invoke retire 65; else invoke retire 0; fi
      ;;
  esac
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
