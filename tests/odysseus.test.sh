#!/usr/bin/env bash
# tests/odysseus.test.sh — end-to-end PVE test for the Odysseus LXC script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test-common.sh"

# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------

SCRIPT_NAME="odysseus"
SERVICES=(odysseus)
REQUIRED_USERS=()
REQUIRED_PATHS=(/opt/odysseus)
WEB_PORT=80
FORBIDDEN_LOG_ERRORS=()
INSTALL_LOG=$(mktemp)

# ------------------------------------------------------------------
echo -e "\n\e[1;36m=== Odysseus Test Suite ===\e[0m"

# Phase 1-2: Preflight
preflight_checks

# Phase 3: Cleanup
phase "3/8" "Destroy old containers"
cleanup_containers "100 101"

# Phase 4: Install
phase "4/8" "Install script"
START=$(date +%s)

pve_exec "
  cd /opt/scripts-underground && git pull --ff-only 2>/dev/null
  TERM=xterm bash -c '
    export TERM=xterm mode=default PHS_SILENT=1 UNATTENDED=1
    export var_os=debian var_version=13
    export var_cpu=2 var_ram=4096 var_disk=8
    export var_unprivileged=1 var_verbose=no
    export var_container_storage=local-lvm var_template_storage=local
    bash scripts/lxc/$SCRIPT_NAME.sh </dev/null 2>&1
  '
" 2>&1 >"$INSTALL_LOG"
ELAPSED=$(($(date +%s) - START))

CTID=$(pve_exec "pct list 2>/dev/null" | awk 'NR>1{print $1; exit}')
if [ -z "$CTID" ]; then
  fail "No container created"
  summary
fi

if grep -q "Completed successfully!" "$INSTALL_LOG"; then
  pass "CT $CTID created in ${ELAPSED}s"
else
  fail "Install did not complete successfully"
  grep -E "failed|error" "$INSTALL_LOG" | tail -5
  summary
fi
rm -f "$INSTALL_LOG"

# Phase 5: Services
phase "5/8" "Services active"
for svc in "${SERVICES[@]}"; do
  check_service "$CTID" "$svc"
done

# Phase 6: Users
phase "6/8" "Required users"
for u in "${REQUIRED_USERS[@]}"; do
  check_user "$CTID" "$u"
done

# Phase 7: Paths
phase "7/8" "Required paths"
for p in "${REQUIRED_PATHS[@]}"; do
  check_path "$CTID" "$p"
done

# Phase 8: Web UI + Logs
phase "8/8" "Web UI"
CTIP=$(pve_pct "$CTID" "hostname -I 2>/dev/null" | awk '{print $1}')
if [ -z "$CTIP" ]; then
  fail "Container IP not available"
  summary
fi

HTTP_CODE=$(pve_exec "curl -sL --connect-timeout 10 -o /dev/null -w '%{http_code}' http://$CTIP:$WEB_PORT/" 2>/dev/null)
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
  pass "Web UI responds on $CTIP:$WEB_PORT (HTTP $HTTP_CODE)"
else
  fail "Web UI not responding (HTTP ${HTTP_CODE:-none})"
fi

# Logs
if [ ${#FORBIDDEN_LOG_ERRORS[@]} -gt 0 ]; then
  for svc in "${SERVICES[@]}"; do
    check_no_log_errors "$CTID" "$svc" "${FORBIDDEN_LOG_ERRORS[@]}"
  done
fi

# ------------------------------------------------------------------
summary
