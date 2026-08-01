#!/usr/bin/env bash
# tests/calibre-web-automated.test.sh — end-to-end PVE test for the CWA LXC script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test-common.sh"

# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------

SCRIPT_NAME="calibre-web-automated"
SERVICES=(calibre-web-automated cwa-ingest                             cwa-auto-zipper cwa-metadata-detector)
REQUIRED_USERS=(abc)
REQUIRED_PATHS=(/app/calibre-web-automated /config /calibre-library /cwa-book-ingest)
WEB_PORT=80
FORBIDDEN_LOG_ERRORS=(
  "chown.*invalid user"
  "Connection refused.*:8083"
  "Calibre library path missing"
)
TEST_BOOK="${TEST_BOOK:-$SCRIPT_DIR/assets/the-raven-noimages.epub}"
INSTALL_LOG=$(mktemp)

# ------------------------------------------------------------------
echo -e "\n\e[1;36m=== CWA Test Suite ===\e[0m"

# Phase 1-2: Preflight
preflight_checks

# Phase 3: Cleanup
phase "3/10" "Destroy old containers"
cleanup_containers "100 101"

# Phase 4: Install
phase "4/10" "Install script"
START=$(date +%s)

pve_exec "
  cd /opt/scripts-underground && git pull --ff-only 2>/dev/null
  TERM=xterm bash -c '
    export TERM=xterm mode=default PHS_SILENT=1 UNATTENDED=1
    export var_os=debian var_version=13
    export var_cpu=2 var_ram=2048 var_disk=8
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
phase "5/10" "Services active"
for svc in "${SERVICES[@]}"; do
  check_service "$CTID" "$svc"
done

# Phase 6: Users
phase "6/10" "Required users"
for u in "${REQUIRED_USERS[@]}"; do
  check_user "$CTID" "$u"
done

# Phase 7: Paths
phase "7/10" "Required paths"
for p in "${REQUIRED_PATHS[@]}"; do
  check_path "$CTID" "$p"
done

# Phase 8: Web UI
phase "8/10" "Web UI"
CTIP=$(pve_pct "$CTID" "hostname -I 2>/dev/null" | awk '{print $1}')
if [ -z "$CTIP" ]; then
  fail "Container IP not available"
  summary
fi

# Curl through PVE — containers on the NAT bridge aren't routable from
# the developer machine directly.
HTTP_CODE=$(pve_exec "curl -sL --connect-timeout 10 -o /dev/null -w '%{http_code}' http://$CTIP:$WEB_PORT/" 2>/dev/null)
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
  pass "Web UI responds on $CTIP:$WEB_PORT (HTTP $HTTP_CODE)"
else
  fail "Web UI not responding (HTTP $HTTP_CODE)"
fi

# Phase 9: Book upload (single pve_exec — PVE can reach the CT directly)
phase "9/10" "Book upload"

PVE_BOOK="/opt/scripts-underground/tests/assets/the-raven-noimages.epub"
pve_exec "
  CTIP=\$(pct exec $CTID -- hostname -I | awk '{print \$1}')
  COOKIE=\$(mktemp)
  curl -s -c \"\$COOKIE\" -o /dev/null http://\$CTIP/login
  L=\$(curl -s -c \"\$COOKIE\" http://\$CTIP/login)
  C=\$(echo \"\$L\" | grep -oP 'name=\"csrf_token\"[^>]*value=\"\\K[^\"]+' | head -1)
  curl -s -b \"\$COOKIE\" -c \"\$COOKIE\" -L -o /dev/null \
    http://\$CTIP/login -d \"csrf_token=\$C&username=admin&password=admin123&remember_me=on&next=/\"
  M=\$(curl -s -b \"\$COOKIE\" http://\$CTIP/)
  B=\$(echo \"\$M\" | grep -oP 'Books \(\d+\)' | head -1)
  C2=\$(echo \"\$M\" | grep -oP 'name=\"csrf_token\"[^>]*value=\"\\K[^\"]+' | head -1)
  U=\$(curl -s -b \"\$COOKIE\" -o /dev/null -w '%{http_code}' \
    http://\$CTIP/upload -F \"csrf_token=\$C2\" -F \"btn-upload=@$PVE_BOOK\")
  sleep 15
  # Fresh cookie jar — the upload session may cache the book count.
  CF=\$(mktemp)
  curl -s -c \"\$CF\" -o /dev/null http://\$CTIP/login
  LL=\$(curl -s -c \"\$CF\" http://\$CTIP/login)
  CC=\$(echo \"\$LL\" | grep -oP 'name=\"csrf_token\"[^>]*value=\"\\K[^\"]+' | head -1)
  curl -s -b \"\$CF\" -c \"\$CF\" -L -o /dev/null \
    http://\$CTIP/login -d \"csrf_token=\$CC&username=admin&password=admin123&remember_me=on&next=/\"
  A=\$(curl -s -b \"\$CF\" http://\$CTIP/ | grep -oP 'Books \(\d+\)' | head -1)
  rm -f \"\$CF\"
  echo \"RESULT:\$U:\$B:\$A\"
  rm -f \"\$COOKIE\"
" >/tmp/cwa-upload-tmp

RESULT=$(cat /tmp/cwa-upload-tmp | grep -oP 'RESULT:\K.*')
UPLOAD_CODE=$(echo "$RESULT" | cut -d: -f1)
BOOK_BEFORE=$(echo "$RESULT" | cut -d: -f2 | grep -oP '\d+')
BOOK_AFTER=$(echo "$RESULT" | cut -d: -f3 | grep -oP '\d+')

if [ "$UPLOAD_CODE" = "200" ]; then
  if [ "${BOOK_AFTER:-0}" -gt "${BOOK_BEFORE:-0}" ]; then
    pass "Book uploaded and ingested ($BOOK_BEFORE → $BOOK_AFTER)"
  else
    warn "Upload accepted but book count unchanged"
  fi
else
  fail "Upload returned HTTP ${UPLOAD_CODE:-unknown}"
fi

# Phase 10: Logs
phase "10/10" "Logs clean"
for svc in calibre-web-automated cwa-ingest; do
  check_no_log_errors "$CTID" "$svc" "${FORBIDDEN_LOG_ERRORS[@]}"
done

# ------------------------------------------------------------------
# Summary
summary
