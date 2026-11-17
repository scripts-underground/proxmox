#!/usr/bin/env bash
# External service model: activation must consume the currently published input.
# Callers own logging, service selection and optional consumer argv/stdout.
fixture_service_state() {
  local action=$1 state=$2
  shift 2
  case "$action" in
    stop) printf stopped > "$state" ;;
    start | restart)
      if (($#)); then "$@" || return $?; fi
      printf running > "$state"
      ;;
  esac
}
