#!/usr/bin/env bash
# External service model: activation must consume the currently published input.
# Callers own logging, service selection and optional consumer argv/stdout.
fixture_service_properties() {
  local active=inactive
  [[ "$(cat "$1")" != running ]] || active=active
  printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=enabled\n' "$active"
}

fixture_service_state() {
  local action=$1 state=$2
  shift 2
  if [[ "$action" == try-restart ]]; then
    [[ -f "$state" && "$(cat "$state")" == running ]] || return 0
    action=restart
  fi
  case "$action" in
    stop) printf stopped > "$state" ;;
    start | restart)
      printf stopped > "$state"
      if (($#)); then "$@" || return $?; fi
      printf running > "$state"
      ;;
  esac
}
