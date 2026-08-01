#!/usr/bin/env bash
# test-common.sh — shared helpers for PVE test scripts.
# Source this from individual test scripts.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
FAILURES=0
PVE_HOST="${PVE_HOST:-192.168.122.50}"

# ------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------

pass() { echo -e "  [\e[32mPASS\e[0m] $*"; }

fail() {
  echo -e "  [\e[31mFAIL\e[0m] $*"
  FAILURES=$((FAILURES + 1))
}

warn() { echo -e "  [\e[33mWARN\e[0m] $*"; }

phase() {
  local num="$1"; shift
  echo -e "\n\e[1m[$num]\e[0m $*"
}

# ------------------------------------------------------------------
# SSH helpers
# ------------------------------------------------------------------

pve_exec() { ssh -o ConnectTimeout=10 root@"$PVE_HOST" "$@" 2>&1; }

pve_pct() {
  local ctid="$1"; shift
  pve_exec "pct exec $ctid -- $*"
}

# ------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------

preflight_checks() {
  phase "1/2" "PVE connectivity"
  if pve_exec hostname | grep -q pve; then
    pass "PVE reachable"
  else
    fail "PVE not reachable at $PVE_HOST"
    exit 1
  fi

  phase "2/2" "Outbound TCP"
  if pve_exec "curl -sI --connect-timeout 5 https://github.com | head -1" | grep -q "HTTP/2 200"; then
    pass "Outbound TCP works"
  else
    fail "Outbound TCP broken"
    exit 1
  fi
}

# ------------------------------------------------------------------
# Container cleanup
# ------------------------------------------------------------------

cleanup_containers() {
  local ctids="${1:-100 101}"
  for id in $ctids; do
    pve_exec "pct shutdown $id --timeout 10 2>/dev/null" || true
  done
  sleep 10
  for id in $ctids; do
    pve_exec "pct destroy $id 2>/dev/null" || true
  done
}

# ------------------------------------------------------------------
# Generic checks
# ------------------------------------------------------------------

check_service() {
  local ctid="$1" svc="$2"
  if pve_pct "$ctid" systemctl is-active "$svc" 2>/dev/null | grep -q active; then
    pass "$svc active"
  else
    fail "$svc inactive"
  fi
}

check_user() {
  local ctid="$1" user="$2"
  if pve_pct "$ctid" id "$user" >/dev/null 2>&1; then
    pass "user $user exists"
  else
    fail "user $user missing"
  fi
}

check_path() {
  local ctid="$1" path="$2"
  if pve_pct "$ctid" test -d "$path"; then
    pass "path $path exists"
  else
    fail "path $path missing"
  fi
}

# ------------------------------------------------------------------
# Log checks
# ------------------------------------------------------------------

check_no_log_errors() {
  local ctid="$1" service="$2"; shift 2
  local patterns=("$@")
  for pat in "${patterns[@]}"; do
    if pve_pct "$ctid" "journalctl -u $service --no-pager -n 100" 2>/dev/null | grep -qE "$pat"; then
      fail "$service: forbidden pattern found: $pat"
    else
      pass "$service: clean ($pat)"
    fi
  done
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

summary() {
  echo
  if [ "$FAILURES" -eq 0 ]; then
    echo -e "\e[1;32m=== All tests PASSED ===\e[0m"
  else
    echo -e "\e[1;31m=== $FAILURES test(s) FAILED ===\e[0m"
  fi
  exit "$FAILURES"
}
