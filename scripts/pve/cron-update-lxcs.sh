#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
#
# This script manages a local cron job for automatic LXC container OS updates.
# The executing manager renders its worker for review and local installation.
# Cron runs that self-contained copy without downloading code.

set -euo pipefail

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
MANAGER_SOURCE="${REPO_BASE}/scripts/pve/cron-update-lxcs.sh"
LOCAL_SCRIPT="/usr/local/bin/update-lxcs.sh"
CONF_FILE="/etc/update-lxcs.conf"
LOG_FILE="/var/log/update-lxcs-cron.log"
CRON_ENTRY="0 0 * * 0 ${LOCAL_SCRIPT} >>${LOG_FILE} 2>&1"

clear
cat << "EOF"
   ______                    __  __          __      __          __   _  ________
  / ____/________  ____     / / / /___  ____/ /___ _/ /____     / /  | |/ / ____/____
 / /   / ___/ __ \/ __ \   / / / / __ \/ __  / __ `/ __/ _ \   / /   |   / /   / ___/
/ /___/ /  / /_/ / / / /  / /_/ / /_/ / /_/ / /_/ / /_/  __/  / /___/   / /___(__  )
\____/_/   \____/_/ /_/   \____/ .___/\__,_/\__,_/\__/\___/  /_____/_/|_\____/____/
                              /_/
EOF

info() { echo -e "\n \e[36m[Info]\e[0m $1"; }
ok() { echo -e " \e[32m[OK]\e[0m $1"; }
err() { echo -e " \e[31m[Error]\e[0m $1" >&2; }

confirm() {
  local prompt="${1:-Proceed?}"
  while true; do
    read -rp " ${prompt} (y/n): " yn || return 1
    case $yn in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "  Please answer yes or no." ;;
    esac
  done
}

# Worker declarations are the sole source for both Add and Update. Nothing from
# the manager UI or its network bootstrap is needed by the installed executable.
cron_worker_id() {
  local id="$1"
  [[ "$id" =~ ^[0-9]+$ ]] || {
    printf 'Invalid excluded CT ID: %s\n' "$id" >&2
    return 65
  }
  while [[ ${#id} -gt 1 && "$id" == 0* ]]; do id="${id#0}"; done
  printf '%s\n' "$id"
}

cron_worker_exclusions() {
  local id line value
  for id in "$@"; do cron_worker_id "$id" || return $?; done
  [[ -e /etc/update-lxcs.conf ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*EXCLUDE[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      printf 'Invalid /etc/update-lxcs.conf: expected literal EXCLUDE=IDs\n' >&2
      return 65
    fi
    value="${BASH_REMATCH[1]}"
    [[ "$value" =~ ^[[:space:]]*$ ]] && continue
    # Do not silently accept an empty component or shell syntax.
    while :; do
      id="${value%%,*}"
      id="${id#"${id%%[![:space:]]*}"}"
      id="${id%"${id##*[![:space:]]}"}"
      cron_worker_id "$id" || return $?
      [[ "$value" == *,* ]] || break
      value="${value#*,}"
    done
  done < /etc/update-lxcs.conf
}

cron_worker_packages() {
  local id="$1" os="$2" phase="${3:-update}"
  if [[ "$phase" == update ]]; then
    # Already-running CTs retain their normal update without a new boot wait.
    case "$os" in
      alpine) pct exec "$id" -- ash -c 'apk -U upgrade' ;;
      archlinux) pct exec "$id" -- sh -c 'pacman -Syu --noconfirm' ;;
      fedora | rocky | centos | alma) pct exec "$id" -- sh -c 'dnf -y upgrade' ;;
      debian | ubuntu | devuan) pct exec "$id" -- sh -c 'apt update && DEBIAN_FRONTEND=noninteractive apt -o Dpkg::Options::=--force-confold dist-upgrade -y' ;;
      opensuse) pct exec "$id" -- sh -c 'zypper --non-interactive refresh && zypper --non-interactive dup' ;;
    esac
    return $?
  fi
  case "$os:$phase" in
    alpine:metadata) set -- apk update ;;
    alpine:upgrade) set -- apk upgrade ;;
    archlinux:metadata) set -- pacman -Sy --noconfirm ;;
    archlinux:upgrade) set -- pacman -Su --noconfirm ;;
    fedora:metadata | rocky:metadata | centos:metadata | alma:metadata)
      set -- dnf -y --refresh '--setopt=*.skip_if_unavailable=False' makecache
      ;;
    fedora:upgrade | rocky:upgrade | centos:upgrade | alma:upgrade)
      set -- dnf -y '--setopt=*.metadata_expire=-1' --setopt=check_config_file_age=False upgrade
      ;;
    debian:metadata | ubuntu:metadata | devuan:metadata)
      set -- apt -o APT::Update::Error-Mode=any update
      ;;
    debian:upgrade | ubuntu:upgrade | devuan:upgrade)
      set -- env DEBIAN_FRONTEND=noninteractive apt -o Dpkg::Options::=--force-confold dist-upgrade -y
      ;;
    opensuse:metadata) set -- zypper --non-interactive refresh --force ;;
    opensuse:upgrade) set -- zypper --non-interactive --no-refresh dup ;;
    *) return 65 ;;
  esac
  if [[ "$phase" == metadata ]]; then
    # The deadline belongs inside the CT: timing out pct alone could leave its
    # package child running. GNU's default group also bounds ordinary descendants.
    pct exec "$id" -- sh -c '
      version=$(LC_ALL=C timeout --version 2>/dev/null) || {
        printf "Metadata readiness requires GNU coreutils timeout (69)\n" >&2
        exit 69
      }
      case "$version" in
        "timeout (GNU coreutils) "*) ;;
        *) printf "Metadata readiness requires GNU coreutils timeout (69)\n" >&2; exit 69 ;;
      esac
      # Keep this shell outside the timed group so a group KILL returns137.
      timeout --kill-after=5 120 "$@"
    ' cron-metadata "$@"
  else
    pct exec "$id" -- "$@"
  fi
}

cron_worker_ready() {
  local id="$1" os="$2" attempt rc=1
  # At most3 full-metadata attempts:120s +5s KILL grace,5s between;385s budget.
  for attempt in 1 2 3; do
    printf 'CT %s metadata readiness attempt %s/3\n' "$id" "$attempt"
    rc=0
    cron_worker_packages "$id" "$os" metadata || rc=$?
    ((rc)) || return 0
    printf 'CT %s metadata attempt %s failed (%s)\n' "$id" "$attempt" "$rc" >&2
    # A missing safe deadline mechanism cannot be retried as an unbounded probe.
    if ((rc == 69 || attempt == 3)); then break; fi
    sleep 5 || return "$rc"
  done
  return "$rc"
}

cron_worker_container() {
  local id="$1" config key value os='' template=0 state rc=0 result=0 started=0 phase=update operation='package update'
  config=$(pct config "$id") || {
    rc=$?
    printf 'CT %s config failed (%s)\n' "$id" "$rc" >&2
    return "$rc"
  }
  while read -r key value; do
    case "$key" in ostype:) os="$value" ;; template:) template="$value" ;; esac
  done <<< "$config"
  case "$template" in
    1)
      printf 'CT %s skipped: template\n' "$id"
      return 0
      ;;
    0) ;;
    *)
      printf 'CT %s refused: unknown template flag (1)\n' "$id" >&2
      return 1
      ;;
  esac
  case "$os" in
    alpine | archlinux | fedora | rocky | centos | alma | debian | ubuntu | devuan | opensuse) ;;
    *)
      printf 'CT %s skipped: unsupported OS %s\n' "$id" "$os"
      return 0
      ;;
  esac
  state=$(pct status "$id") || {
    rc=$?
    printf 'CT %s status failed (%s)\n' "$id" "$rc" >&2
    return "$rc"
  }
  case "$state" in
    'status: running') ;;
    'status: stopped')
      pct start "$id" || {
        rc=$?
        printf 'CT %s start failed (%s)\n' "$id" "$rc" >&2
        return "$rc"
      }
      # Own the successful start before any fallible observation. Only a proven
      # non-running result cancels restoration eligibility; query errors do not.
      started=1
      operation='start observation'
      state=$(pct status "$id") || result=$?
      if ((result == 0)) && [[ "$state" != 'status: running' ]]; then
        started=0
        result=1
        printf 'CT %s refused: start did not reach running (1)\n' "$id" >&2
      fi
      ;;
    *)
      printf 'CT %s refused: unknown state %s (1)\n' "$id" "$state" >&2
      return 1
      ;;
  esac
  if ((started && result == 0)); then
    phase=upgrade
    operation='metadata readiness'
    cron_worker_ready "$id" "$os" || result=$?
  fi
  if ((result == 0)); then
    operation='package update'
    cron_worker_packages "$id" "$os" "$phase" || result=$?
  fi
  if ((result)); then
    printf 'CT %s %s failed (%s)\n' "$id" "$operation" "$result" >&2
  else printf 'CT %s packages updated\n' "$id"; fi
  if ((started)); then
    # Synchronous bounded graceful restoration only for a checked successful start.
    rc=0
    pct shutdown "$id" --timeout 60 --forceStop 0 || rc=$?
    if ((rc == 0)); then
      state=$(pct status "$id") || rc=$?
      if ((rc == 0)) && [[ "$state" != 'status: stopped' ]]; then rc=1; fi
    fi
    if ((rc)); then
      printf 'CT %s shutdown/restoration failed (%s); no forced stop\n' "$id" "$rc" >&2
    else printf 'CT %s restored to stopped\n' "$id"; fi
    ((result)) || result=$rc
  fi
  return "$result"
}

cron_worker_main() {
  local exclusions listing id rest rc first=1 result=0
  local -A excluded=() seen=()
  exclusions=$(cron_worker_exclusions "$@") || return $?
  while IFS= read -r id; do [[ -z "$id" ]] || excluded["$id"]=1; done <<< "$exclusions"
  listing=$(pct list) || return $?
  # pct list's header is not a target. Every remaining ID is validated before use.
  while read -r id rest; do
    if ((first)); then
      first=0
      continue
    fi
    [[ -n "$id" ]] || continue
    if [[ ! "$id" =~ ^[0-9]+$ || -n "${seen[$id]:-}" ]]; then
      printf 'Refused malformed/duplicate CT list entry (1)\n' >&2
      ((result)) || result=1
      continue
    fi
    seen["$id"]=1
    if [[ -n "${excluded[$id]:-}" ]]; then
      printf 'CT %s skipped: excluded\n' "$id"
      continue
    fi
    rc=0
    cron_worker_container "$id" || rc=$?
    if ((rc && result == 0)); then result=$rc; fi
  done <<< "$listing"
  return "$result"
}

worker_contents() {
  printf '#!/usr/bin/env bash\n# Generated from the executing cron-update-lxcs.sh manager.\nset -uo pipefail\n' || return $?
  declare -f cron_worker_id cron_worker_exclusions cron_worker_packages cron_worker_ready cron_worker_container cron_worker_main || return $?
  printf '\ncron_worker_main "$@"\n' || return $?
}

prepare_script() {
  local tmp rc=0
  tmp=$(mktemp "${LOCAL_SCRIPT%/*}/.update-lxcs.XXXXXX") || return $?
  worker_contents > "$tmp" || rc=$?
  if ((rc)); then
    rm -f -- "$tmp"
    return "$rc"
  fi
  printf '%s\n' "$tmp"
}

publish_script() {
  local tmp="$1" rc=0
  chmod 0755 "$tmp" || rc=$?
  if ((rc == 0)); then mv -fT -- "$tmp" "$LOCAL_SCRIPT" || rc=$?; fi
  if ((rc)); then
    rm -f -- "$tmp"
    return "$rc"
  fi
}

review_script() {
  local file="$1"
  local hash
  hash=$(sha256sum "$file" | awk '{print $1}')
  echo ""
  echo -e " \e[1;33m─── Script Content ───────────────────────────────────────────\e[0m"
  cat "$file"
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo -e " \e[36mSHA256:\e[0m ${hash}"
  echo -e " \e[36mGenerated by executing manager:\e[0m ${MANAGER_SOURCE}"
  echo ""
}

remove_legacy_cron() {
  if crontab -l -u root 2> /dev/null | grep -q "update-lxcs-cron.sh"; then
    (crontab -l -u root 2> /dev/null | grep -v "update-lxcs-cron.sh" || true) | crontab -u root -
    ok "Removed legacy curl-based cron entry"
  fi
}

add() {
  info "Preparing self-contained update script..."
  local tmp
  tmp=$(prepare_script) || return $?

  local hash
  hash=$(sha256sum "$tmp" | awk '{print $1}')
  echo ""
  echo -e " \e[1;33m─── Installation Summary ─────────────────────────────────────\e[0m"
  echo -e " \e[36mManager source:\e[0m ${MANAGER_SOURCE}"
  echo -e " \e[36mSHA256:\e[0m       ${hash}"
  echo -e " \e[36mInstall to:\e[0m   ${LOCAL_SCRIPT}"
  echo -e " \e[36mConfig:\e[0m       ${CONF_FILE}"
  echo -e " \e[36mLog file:\e[0m     ${LOG_FILE}"
  echo -e " \e[36mCron schedule:\e[0m Every Sunday at midnight (0 0 * * 0)"
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo ""

  if confirm "Review script content before installing?"; then
    review_script "$tmp"
  fi

  if ! confirm "Install this script and activate cron schedule?"; then
    rm -f "$tmp"
    echo " Aborted."
    exit 0
  fi

  publish_script "$tmp" || return $?
  ok "Installed script to ${LOCAL_SCRIPT}"

  remove_legacy_cron

  if [[ ! -f "$CONF_FILE" ]]; then
    cat > "$CONF_FILE" << 'CONF'
# Configuration for automatic LXC container OS updates.
# Add container IDs to exclude from updates (comma-separated):
# EXCLUDE=100,101,102
EXCLUDE=
CONF
    ok "Created config ${CONF_FILE}"
  fi

  (
    crontab -l -u root 2> /dev/null | grep -v "${LOCAL_SCRIPT}" || true
    echo "${CRON_ENTRY}"
  ) | crontab -u root -
  ok "Added cron schedule: Every Sunday at midnight"
  echo ""
  echo -e " \e[36mLocal script:\e[0m ${LOCAL_SCRIPT}"
  echo -e " \e[36mConfig:\e[0m      ${CONF_FILE}"
  echo -e " \e[36mLog file:\e[0m    ${LOG_FILE}"
  echo ""
}

remove() {
  if crontab -l -u root 2> /dev/null | grep -q "${LOCAL_SCRIPT}"; then
    (crontab -l -u root 2> /dev/null | grep -v "${LOCAL_SCRIPT}" || true) | crontab -u root -
    ok "Removed cron schedule"
  fi
  remove_legacy_cron
  [[ -f "$LOCAL_SCRIPT" ]] && rm -f "$LOCAL_SCRIPT" && ok "Removed ${LOCAL_SCRIPT}"
  [[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE" && ok "Removed ${LOG_FILE}"
  echo -e "\n Cron Update LXCs has been fully removed."
  echo -e " \e[90mNote: ${CONF_FILE} was kept (remove manually if desired).\e[0m"
}

update_script() {
  if [[ ! -f "$LOCAL_SCRIPT" ]]; then
    err "No local script found at ${LOCAL_SCRIPT}. Use 'Add' first."
    exit 1
  fi

  info "Preparing worker from this manager revision..."
  local tmp
  tmp=$(prepare_script) || return $?

  if command -v diff &> /dev/null; then
    local changes
    changes=$(diff --color=auto "$LOCAL_SCRIPT" "$tmp" 2> /dev/null || true)
    if [[ -z "$changes" ]]; then
      ok "Script is already up-to-date (no changes)."
      rm -f "$tmp"
      return
    fi
    echo ""
    echo -e " \e[1;33m─── Changes ──────────────────────────────────────────────────\e[0m"
    echo "$changes"
    echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  else
    review_script "$tmp"
  fi

  local new_hash old_hash
  new_hash=$(sha256sum "$tmp" | awk '{print $1}')
  old_hash=$(sha256sum "$LOCAL_SCRIPT" | awk '{print $1}')
  echo -e " \e[36mCurrent SHA256:\e[0m ${old_hash}"
  echo -e " \e[36mNew SHA256:\e[0m     ${new_hash}"
  echo ""

  if ! confirm "Apply update?"; then
    rm -f "$tmp"
    echo " Aborted."
    return
  fi

  publish_script "$tmp" || return $?
  ok "Updated ${LOCAL_SCRIPT}"
}

view_script() {
  if [[ ! -f "$LOCAL_SCRIPT" ]]; then
    err "No local script found at ${LOCAL_SCRIPT}. Use 'Add' first."
    exit 1
  fi

  local view_choice
  view_choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "View Script" --menu "What do you want to view?" 12 60 3 \
    "Worker" "Installed update script (${LOCAL_SCRIPT##*/})" \
    "Cron" "Cron schedule & configuration" \
    "Both" "Show everything" \
    3>&1 1>&2 2>&3) || return 0

  case "$view_choice" in
    "Worker") view_worker_script ;;
    "Cron") view_cron_config ;;
    "Both") view_cron_config && echo "" && view_worker_script ;;
  esac
}

view_worker_script() {
  local hash
  hash=$(sha256sum "$LOCAL_SCRIPT" | awk '{print $1}')
  echo ""
  echo -e " \e[1;33m─── ${LOCAL_SCRIPT} ───\e[0m"
  cat "$LOCAL_SCRIPT"
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo -e " \e[36mSHA256:\e[0m    ${hash}"
  echo -e " \e[36mInstalled:\e[0m $(stat -c '%y' "$LOCAL_SCRIPT" 2> /dev/null | cut -d. -f1)"
  echo ""
}

view_cron_config() {
  echo ""
  echo -e " \e[1;33m─── Cron Configuration ───────────────────────────────────────\e[0m"
  if crontab -l -u root 2> /dev/null | grep -q "${LOCAL_SCRIPT}"; then
    local entry
    entry=$(crontab -l -u root 2> /dev/null | grep "${LOCAL_SCRIPT}")
    echo -e " \e[36mCron entry:\e[0m  ${entry}"
    local schedule
    schedule=$(echo "$entry" | awk '{print $1,$2,$3,$4,$5}')
    echo -e " \e[36mSchedule:\e[0m    ${schedule} ($(cron_to_human "$schedule"))"
  else
    echo -e " \e[31mCron:\e[0m        Not configured"
  fi
  if [[ -f "$CONF_FILE" ]]; then
    echo -e " \e[36mConfig file:\e[0m ${CONF_FILE}"
    local excludes
    excludes=$(grep -oP '^\s*EXCLUDE\s*=\s*\K.*' "$CONF_FILE" 2> /dev/null || true)
    echo -e " \e[36mExcluded:\e[0m    ${excludes:-(none)}"
    echo ""
    echo -e " \e[90m--- ${CONF_FILE} ---\e[0m"
    cat "$CONF_FILE"
  else
    echo -e " \e[36mConfig file:\e[0m (not created yet)"
  fi
  if [[ -f "$LOG_FILE" ]]; then
    local log_size
    log_size=$(du -h "$LOG_FILE" | awk '{print $1}')
    echo -e " \e[36mLog file:\e[0m    ${LOG_FILE} (${log_size})"
  fi
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo ""
}

cron_to_human() {
  local schedule="$1"
  case "$schedule" in
    "0 0 * * 0") echo "Every Sunday at midnight" ;;
    "0 0 * * *") echo "Daily at midnight" ;;
    "0 * * * *") echo "Every hour" ;;
    *) echo "Custom schedule" ;;
  esac
}

show_status() {
  echo ""
  if [[ -f "$LOCAL_SCRIPT" ]]; then
    local hash
    hash=$(sha256sum "$LOCAL_SCRIPT" | awk '{print $1}')
    ok "Script installed: ${LOCAL_SCRIPT}"
    echo -e "   \e[36mSHA256:\e[0m    ${hash}"
    echo -e "   \e[36mInstalled:\e[0m $(stat -c '%y' "$LOCAL_SCRIPT" 2> /dev/null | cut -d. -f1)"
  else
    err "Script not installed"
  fi

  if crontab -l -u root 2> /dev/null | grep -q "${LOCAL_SCRIPT}"; then
    local schedule
    schedule=$(crontab -l -u root 2> /dev/null | grep "${LOCAL_SCRIPT}" | awk '{print $1,$2,$3,$4,$5}')
    ok "Cron active: ${schedule}"
  else
    err "Cron not configured"
  fi

  if [[ -f "$CONF_FILE" ]]; then
    local excludes
    excludes=$(grep -oP '^\s*EXCLUDE\s*=\s*\K.*' "$CONF_FILE" 2> /dev/null || echo "(none)")
    echo -e "   \e[36mExcluded:\e[0m  ${excludes:-"(none)"}"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    local log_size last_run
    log_size=$(du -h "$LOG_FILE" | awk '{print $1}')
    last_run=$(grep -oP '^\s+\K\w.*' "$LOG_FILE" | tail -1)
    echo -e "   \e[36mLog file:\e[0m  ${LOG_FILE} (${log_size})"
    [[ -n "${last_run:-}" ]] && echo -e "   \e[36mLast run:\e[0m  ${last_run}"
  else
    echo -e "   \e[36mLog file:\e[0m  (no runs yet)"
  fi
  echo ""
}

run_now() {
  if [[ ! -f "$LOCAL_SCRIPT" ]]; then
    err "No local script found at ${LOCAL_SCRIPT}. Use 'Add' first."
    exit 1
  fi
  info "Running update script now..."
  bash "$LOCAL_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
  ok "Run completed. Log appended to ${LOG_FILE}"
}

rotate_log() {
  if [[ ! -f "$LOG_FILE" ]]; then
    info "No log file to rotate."
    return
  fi
  local log_size
  log_size=$(stat -c '%s' "$LOG_FILE" 2> /dev/null || echo 0)
  local log_size_h
  log_size_h=$(du -h "$LOG_FILE" | awk '{print $1}')
  if confirm "Rotate log file? (current size: ${log_size_h})"; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    ok "Rotated: ${LOG_FILE} → ${LOG_FILE}.old"
  fi
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/pve") 2> /dev/null

OPTIONS=(
  Add "Prepare, review & install cron schedule"
  Remove "Remove cron schedule & local script"
  Update "Update local worker from this manager"
  Status "Show installation status & last run"
  Run "Run update script now (manual trigger)"
  View "View cron config & installed script"
  Rotate "Rotate log file"
)

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Cron Update LXCs" --menu "Select an option:" 16 68 7 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3) || exit 0

case $CHOICE in
  "Add") add ;;
  "Remove") remove ;;
  "Update") update_script ;;
  "Status") show_status ;;
  "Run") run_now ;;
  "View") view_script ;;
  "Rotate") rotate_log ;;
esac
