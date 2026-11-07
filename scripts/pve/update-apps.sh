#!/usr/bin/env bash
# shellcheck disable=SC2046,SC2034,SC2164
# shellcheck disable=SC2034,SC2164

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BvdBerg01 | Co-Author: remz1337
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/core.func")

# =============================================================================
# CONFIGURATION VARIABLES
# Set these variables to skip interactive prompts (Whiptail dialogs)
# =============================================================================
# var_backup: Enable/disable backup before update
#   Options: "yes" | "no" | "" (empty = interactive prompt)
var_backup="${var_backup:-}"

# var_backup_storage: Storage location for backups (only used if var_backup=yes)
#   Options: Storage name from /etc/pve/storage.cfg (e.g., "local", "nas-backup")
#   Leave empty for interactive selection
var_backup_storage="${var_backup_storage:-}"

# var_container: Which containers to update
#   Options:
#     - "all"         : All containers with scripts-underground tags
#     - "all_running" : Only running containers with scripts-underground tags
#     - "all_stopped" : Only stopped containers with scripts-underground tags
#     - "101,102,109" : Comma-separated list of specific container IDs
#     - ""            : Interactive selection via Whiptail
var_container="${var_container:-}"

# var_unattended: Run updates without user interaction inside containers
#   Options: "yes" | "no" | "" (empty = interactive prompt)
var_unattended="${var_unattended:-}"

# var_skip_confirm: Skip initial confirmation dialog
#   Options: "yes" | "no" (default: no)
var_skip_confirm="${var_skip_confirm:-no}"

# var_auto_reboot: Automatically reboot containers that require it after update
#   Options: "yes" | "no" | "" (empty = interactive prompt)
var_auto_reboot="${var_auto_reboot:-}"

# =============================================================================
# JSON CONFIG EXPORT
# Run with --export-config to output current configuration as JSON
# =============================================================================

function export_config_json() {
  cat << EOF
{
  "var_backup": "${var_backup}",
  "var_backup_storage": "${var_backup_storage}",
  "var_container": "${var_container}",
  "var_unattended": "${var_unattended}",
  "var_skip_confirm": "${var_skip_confirm}",
  "var_auto_reboot": "${var_auto_reboot}"
}
EOF
}

function print_usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Update LXC containers created with scripts-underground.

Options:
  --help              Show this help message
  --export-config     Export current configuration as JSON

Environment Variables:
  var_backup          Enable backup before update (yes/no)
  var_backup_storage  Storage location for backups
  var_container       Container selection (all/all_running/all_stopped/101,102,...)
  var_unattended      Run updates unattended (yes/no)
  var_skip_confirm    Skip initial confirmation (yes/no)
  var_auto_reboot     Auto-reboot containers if required (yes/no)

Examples:
  # Run interactively
  $(basename "$0")

  # Update all running containers unattended with backup
  var_backup=yes var_backup_storage=local var_container=all_running var_unattended=yes var_skip_confirm=yes $(basename "$0")

  # Update specific containers without backup
  var_backup=no var_container=101,102,105 var_unattended=yes var_skip_confirm=yes $(basename "$0")

  # Export current configuration
  $(basename "$0") --export-config
EOF
}

# Handle command line arguments
case "${1:-}" in
  --help | -h)
    print_usage
    exit 0
    ;;
  --export-config)
    export_config_json
    exit 0
    ;;
esac

# =============================================================================

function header_info {
  terminal_clear
  cat << "EOF"
    __   _  ________   __  __          __      __
   / /  | |/ / ____/  / / / /___  ____/ /___ _/ /____
  / /   |   / /      / / / / __ \/ __  / __ `/ __/ _ \
 / /___/   / /___   / /_/ / /_/ / /_/ / /_/ / /_/  __/
/_____/_/|_\____/   \____/ .___/\__,_/\__,_/\__/\___/
                        /_/
EOF
}

function detect_service() {
  service=''
  local LC_ALL=C _ds_stage _ds_text='' _ds_line='' _ds_result='' _ds_status=0 _ds_cleanup=0
  local _ds_baked=0 _ds_bad=0 _ds_legacy=0 _ds_other=0 _ds_legacy_name=''
  local _ds_baked_re='^declare -- NSAPP=([a-z0-9][a-z0-9._-]{0,63})$'
  local _ds_ignore_re='^[[:space:]]*(#|$)'
  local _ds_legacy_re='^[[:space:]]*bash[[:space:]]+-c[[:space:]]+"\$\(curl[[:space:]]+-fsSL[[:space:]]+https?://[A-Za-z0-9._~:/%+-]+/ct/([a-z0-9][a-z0-9._-]{0,63})\.sh\)"[[:space:]]*$'
  _ds_stage=$(mktemp "${TMPDIR:-/tmp}/update-apps-service.XXXXXXXX") || return $?
  if pct pull "$1" /usr/bin/update "$_ds_stage" 2> /dev/null; then
    if [[ ! -f "$_ds_stage" || -L "$_ds_stage" ]]; then
      _ds_status=65
    elif IFS= read -r -d '' _ds_line < "$_ds_stage"; then
      # Updaters are text. Do not silently discard NUL bytes during capture.
      _ds_status=65
    elif _ds_text=$(cat -- "$_ds_stage"); then
      while IFS= read -r _ds_line || [[ -n "$_ds_line" ]]; do
        [[ "$_ds_line" =~ $_ds_ignore_re ]] && continue
        if [[ "$_ds_line" =~ ^[[:space:]]*(declare|export|readonly)[[:space:]] &&
          "$_ds_line" =~ [[:space:]]NSAPP([[:space:]]|=|$) ]] || [[ "$_ds_line" =~ ^[[:space:]]*NSAPP[[:space:]]*= ]]; then
          _ds_baked=$((_ds_baked + 1))
          if [[ "$_ds_line" =~ $_ds_baked_re ]]; then
            _ds_result=${BASH_REMATCH[1]}
          else
            _ds_bad=1
          fi
        elif [[ "$_ds_line" =~ $_ds_legacy_re ]]; then
          _ds_legacy=$((_ds_legacy + 1))
          _ds_legacy_name=${BASH_REMATCH[1]}
        else
          _ds_other=1
        fi
      done <<< "$_ds_text"
      if [[ "$_ds_baked" -gt 0 ]]; then
        [[ "$_ds_baked" == 1 && "$_ds_bad" == 0 ]] || _ds_status=65
      elif [[ "$_ds_legacy" == 1 && "$_ds_other" == 0 ]]; then
        _ds_result=$_ds_legacy_name
      else
        _ds_status=65
      fi
    else
      _ds_status=$?
    fi
  else
    _ds_status=$?
  fi
  rm -f -- "$_ds_stage" || _ds_cleanup=$?
  [[ "$_ds_status" != 0 || "$_ds_cleanup" == 0 ]] || _ds_status=$_ds_cleanup
  if [[ "$_ds_status" == 0 ]]; then
    service=$_ds_result
  else
    printf 'Unable to identify updater for container %s (status %s).\n' "$1" "$_ds_status" >&2
  fi
  return "$_ds_status"
}

# Script declarations are data only, never shell source or sizing instructions.
# Accept one literal declaration per dimension; missing/ambiguous data is unknown.
function read_batch_requirements() {
  local _br_line _br_key _br_value _br_count _br_re _br_literal
  required_cpu='' required_ram=''
  for _br_key in cpu ram; do
    _br_count=0 _br_value=''
    _br_re='^[[:space:]]*var_'"$_br_key"'="\$\{var_'"$_br_key"':-([0-9]+)\}"[[:space:]]*(#.*)?$'
    _br_literal='^[[:space:]]*var_'"$_br_key"'="([0-9]+)"[[:space:]]*(#.*)?$'
    while IFS= read -r _br_line || [[ -n "$_br_line" ]]; do
      if [[ "$_br_line" =~ ^[[:space:]]*var_${_br_key}= ]]; then
        _br_count=$((_br_count + 1))
        if [[ "$_br_line" =~ $_br_re || "$_br_line" =~ $_br_literal ]]; then
          _br_value=${BASH_REMATCH[1]}
        else
          _br_count=$((_br_count + 2))
        fi
      fi
    done <<< "$1"
    [[ "$_br_count" == 1 ]] || _br_value=''
    printf -v "required_$_br_key" '%s' "$_br_value"
  done
}

function admit_batch_update() {
  local _ba_script _ba_free _ba_cpu _ba_ram _ba_status
  required_cpu='' required_ram=''
  if _ba_script=$(curl -fsSL "$REPO_BASE/scripts/lxc/${service}.sh"); then
    read_batch_requirements "$_ba_script"
  else
    _ba_status=$?
    printf 'Warning: metadata download failed for container %s (status %s); requirements are unknown.\n' "$container" "$_ba_status" >&2
  fi
  _ba_cpu=$(pct exec "$container" -- nproc) || return $?
  _ba_free=$(pct exec "$container" -- free -m) || return $?
  _ba_ram=$(awk 'NR==2{print $2}' <<< "$_ba_free") || return $?
  if confirm_container_resources "$required_cpu" "$required_ram" "$_ba_cpu" "$_ba_ram" "Container $container ($service)"; then
    return 0
  else
    _ba_status=$?
    [[ "$_ba_status" != 1 ]] || admission_declined=1
    return "$_ba_status"
  fi
}

# Only a successfully owned pre-update start may be restored on admission refusal.
function restore_batch_start() {
  local _bs_status
  [[ "$batch_started" == 1 ]] || return 0
  printf 'Restoring batch-started container %s to stopped state before update.\n' "$container" >&2
  pct shutdown "$container" --timeout 60 || return $?
  _bs_status=$(pct status "$container") || return $?
  [[ "$_bs_status" == 'status: stopped' ]] || return 69
}

function continue_batch_updates() {
  local _bc_prompt=''
  [[ "$((batch_index + 1))" -lt "${#batch_targets[@]}" ]] || return 0
  printf 'Continue with the remaining selected containers? <yes/No> ' >&2
  if IFS= read -r _bc_prompt; then
    case "${_bc_prompt,,}" in y | yes) return 0 ;; esac
  fi
  containers_not_attempted+=("${batch_targets[@]:batch_index+1}")
  return 1
}

# Every terminal exit after work begins uses the same outcome priority. Fatal
# callers still exit immediately: selection adds no PVE or reboot effects.
function exit_batch_update() {
  local _bx_fallback=$1
  if [[ "${2:-}" == abort ]]; then
    printf 'Batch partially complete; aborted at container %s. Later selected containers were not attempted.\n' "$container" >&2
  fi
  if [[ "${#containers_skipped_temporary[@]}" -gt 0 ]]; then
    exit 75
  fi
  [[ "$first_admission_status" == 0 ]] || exit "$first_admission_status"
  exit "$_bx_fallback"
}

function backup_container() {
  msg_info "Creating backup for container $1"
  vzdump $1 --compress zstd --storage $STORAGE_CHOICE -notes-template "scripts-underground backup updater" > /dev/null 2>&1
  status=$?

  if [ $status -eq 0 ]; then
    msg_ok "Backup created"
  else
    msg_error "Backup failed for container $1"
    exit_batch_update 1 abort
  fi
}

function get_backup_storages() {
  STORAGES=$(awk '
/^[a-z]+:/ {
    if (name != "") {
        if (has_backup || (!has_content && type == "dir")) print name
    }
    split($0, a, ":")
    type = a[1]
    name = a[2]
    sub(/^ +/, "", name)
    has_content = 0
    has_backup = 0
}
/^ +content/ {
    has_content = 1
    if ($0 ~ /backup/) has_backup = 1
}
END {
    if (name != "") {
        if (has_backup || (!has_content && type == "dir")) print name
    }
}
' /etc/pve/storage.cfg)
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/pve") 2> /dev/null

header_info

if [[ "$var_skip_confirm" != "yes" ]]; then
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "This will update LXC container. Proceed?" 10 58 || exit
fi

msg_info "Loading all possible LXC containers from Proxmox VE. This may take a few seconds..."
NODE=$(hostname)
containers=$(pct list | tail -n +2 | awk '{print $0 " " $4}')

if [ -z "$containers" ]; then
  whiptail --title "LXC Container Update" --msgbox "No LXC containers available!" 10 60
  exit 1
fi

menu_items=()
FORMAT="%-10s %-15s %-10s"
TAGS="community-script|proxmox-helper-scripts"

while read -r container; do
  container_id=$(echo $container | awk '{print $1}')
  container_name=$(echo $container | awk '{print $2}')
  container_status=$(echo $container | awk '{print $3}')
  formatted_line=$(printf "$FORMAT" "$container_name" "$container_status")
  if pct config "$container_id" | grep -qE "^tags:.*(${TAGS}).*"; then
    menu_items+=("$container_id" "$formatted_line" "OFF")
  fi
done <<< "$containers"
msg_ok "Loaded ${#menu_items[@]} containers"

if [[ -n "$var_container" ]]; then
  case "$var_container" in
    all)
      CHOICE=""
      for ((i = 0; i < ${#menu_items[@]}; i += 3)); do
        CHOICE="$CHOICE ${menu_items[$i]}"
      done
      CHOICE=$(echo "$CHOICE" | xargs)
      ;;
    all_running)
      CHOICE=""
      for ((i = 0; i < ${#menu_items[@]}; i += 3)); do
        cid="${menu_items[$i]}"
        if pct status "$cid" 2> /dev/null | grep -q "running"; then
          CHOICE="$CHOICE $cid"
        fi
      done
      CHOICE=$(echo "$CHOICE" | xargs)
      ;;
    all_stopped)
      CHOICE=""
      for ((i = 0; i < ${#menu_items[@]}; i += 3)); do
        cid="${menu_items[$i]}"
        if pct status "$cid" 2> /dev/null | grep -q "stopped"; then
          CHOICE="$CHOICE $cid"
        fi
      done
      CHOICE=$(echo "$CHOICE" | xargs)
      ;;
    *)
      CHOICE=$(echo "$var_container" | tr ',' ' ')
      ;;
  esac

  if [[ -z "$CHOICE" ]]; then
    msg_error "No containers matched the selection criteria: $var_container"
    exit 1
  fi
  msg_ok "Selected containers: $CHOICE"
else
  CHOICE=$(whiptail --title "LXC Container Update" \
    --checklist "Select LXC containers to update:" 25 60 13 \
    "${menu_items[@]}" 3>&2 2>&1 1>&3 | tr -d '"')

  if [ -z "$CHOICE" ]; then
    whiptail --title "LXC Container Update" \
      --msgbox "No containers selected!" 10 60
    exit 1
  fi
fi

header_info

if [[ -n "$var_backup" ]]; then
  BACKUP_CHOICE="$var_backup"
else
  BACKUP_CHOICE="no"
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "Do you want to backup your containers before update?" 10 58); then
    BACKUP_CHOICE="yes"
  fi
fi

if [[ -n "$var_unattended" ]]; then
  UNATTENDED_UPDATE="$var_unattended"
else
  UNATTENDED_UPDATE="no"
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "Run updates unattended?" 10 58); then
    UNATTENDED_UPDATE="yes"
  fi
fi

if [ "$BACKUP_CHOICE" == "yes" ]; then
  get_backup_storages

  if [ -z "$STORAGES" ]; then
    msg_error "No storage with 'backup' support found!"
    exit 1
  fi

  if [[ -n "$var_backup_storage" ]]; then
    if echo "$STORAGES" | grep -qw "$var_backup_storage"; then
      STORAGE_CHOICE="$var_backup_storage"
      msg_ok "Using backup storage: $STORAGE_CHOICE"
    else
      msg_error "Specified backup storage '$var_backup_storage' not found or doesn't support backups!"
      msg_info "Available storages: $(echo $STORAGES | tr '\n' ' ')"
      exit 1
    fi
  else
    MENU_ITEMS=()
    for STORAGE in $STORAGES; do
      MENU_ITEMS+=("$STORAGE" "")
    done

    STORAGE_CHOICE=$(whiptail --title "Select storage device" --menu "Select a storage device (Only storage devices with 'backup' support are listed):" 15 50 5 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$STORAGE_CHOICE" ]; then
      msg_error "No storage selected!"
      exit 1
    fi
  fi
fi

UPDATE_CMD="update;"
if [ "$UNATTENDED_UPDATE" == "yes" ]; then
  UPDATE_CMD="export PHS_SILENT=1;update;"
fi

containers_needing_reboot=()
containers_skipped_temporary=()
containers_declined=()
containers_admission_failed=()
containers_update_failed=()
containers_not_attempted=()
first_admission_status=0 normal_result=0
read -r -a batch_targets <<< "$CHOICE"
for ((batch_index = 0; batch_index < ${#batch_targets[@]}; batch_index++)); do
  container=${batch_targets[$batch_index]}
  batch_started=0
  admission_status=0
  admission_declined=0
  echo -e "${BL}[INFO]${CL} Updating container $container"

  if [ "$BACKUP_CHOICE" == "yes" ]; then
    backup_container $container
  fi

  config=$(pct config "$container") || admission_status=$?
  os=$(awk '/^ostype/ {print $2}' <<< "$config")
  status=$(pct status "$container") || admission_status=$?
  template=false
  [[ "$config" != *'template:'* ]] || template=true
  if [[ "$admission_status" == 0 && "$template" == false && "$status" == 'status: stopped' ]]; then
    echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL} \n"
    if pct start "$container"; then batch_started=1; else admission_status=$?; fi
    echo -e "${BL}[Info]${GN} Waiting For${BL} $container${CL}${GN} To Start ${CL} \n"
    sleep 5
  fi

  if [[ "$admission_status" != 0 ]]; then
    :
  elif detect_service "$container"; then
    echo -e "${BL}[INFO]${CL} Detected service: ${GN}${service}${CL}"
    if admit_batch_update; then :; else admission_status=$?; fi
  else
    admission_status=$?
  fi

  if [[ "$admission_status" != 0 ]]; then
    [[ "$first_admission_status" != 0 ]] || first_admission_status=$admission_status
    if [[ "$admission_declined" == 1 ]]; then
      containers_declined+=("$container")
      printf 'Container %s declined; no software update attempted.\n' "$container" >&2
    else
      containers_admission_failed+=("$container")
      printf 'Container %s admission failed (status %s); no software update attempted.\n' "$container" "$admission_status" >&2
    fi
    if restore_batch_start; then :; else
      cleanup_status=$?
      printf 'Container %s: unable to restore batch-owned start (status %s); inspect its actual state.\n' "$container" "$cleanup_status" >&2
    fi
    if continue_batch_updates; then continue; else break; fi
  fi

  case "$os" in
    alpine) pct exec "$container" -- ash -c "$UPDATE_CMD" ;;
    archlinux) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
    fedora | rocky | centos | alma) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
    ubuntu | debian | devuan) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
    opensuse) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
    *) false ;;
  esac
  exit_code=$?

  # A competing maintenance owner may still be modifying this CT. Status75 can
  # also be an app's temporary failure: neither permits automatic rollback.
  if [ "$exit_code" -eq 75 ]; then
    printf 'Container %s temporarily unavailable/busy (status75); skipped without automatic rollback, shutdown or reboot. Any backup already taken is retained.\n' "$container" >&2
    if [ "$batch_started" -eq 1 ]; then
      printf 'Container %s: this batch started it; it is left running.\n' "$container" >&2
    fi
    containers_skipped_temporary+=("$container")
    continue
  fi

  if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
    echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL} \n"
    pct shutdown $container &
  fi

  if pct exec "$container" -- [ -e "/var/run/reboot-required" ]; then
    container_hostname=$(pct exec "$container" hostname)
    containers_needing_reboot+=("$container ($container_hostname)")
  fi

  if [ $exit_code -eq 0 ]; then
    msg_ok "Updated container $container"
  elif [ "$BACKUP_CHOICE" == "yes" ]; then
    containers_update_failed+=("$container")
    normal_result=1
    msg_info "Restoring LXC from backup"
    pct stop $container
    LXC_STORAGE=$(pct config $container | awk -F '[:,]' '/rootfs/ {print $2}')
    pct restore $container /var/lib/vz/dump/vzdump-lxc-${container}-*.tar.zst --storage $LXC_STORAGE --force > /dev/null 2>&1
    pct start $container
    restorestatus=$?
    if [ $restorestatus -eq 0 ]; then
      msg_ok "Restored LXC from backup"
    else
      msg_error "Restored LXC from backup failed"
      exit_batch_update 1 abort
    fi
  else
    containers_update_failed+=("$container")
    normal_result=1
    msg_error "Update failed for container $container. Stopping"
    containers_not_attempted+=("${batch_targets[@]:batch_index+1}")
    exit_batch_update 1 abort
  fi
done

wait
header_info
if [[ "${#containers_skipped_temporary[@]}" -gt 0 || "$first_admission_status" != 0 || "$normal_result" != 0 ]]; then
  printf 'Batch partially complete; temporary/busy skips (not updated): %s; declined: %s; failed admission: %s; failed updates: %s; not attempted: %s.\n' "${containers_skipped_temporary[*]:-none}" "${containers_declined[*]:-none}" "${containers_admission_failed[*]:-none}" "${containers_update_failed[*]:-none}" "${containers_not_attempted[*]:-none}"
else
  echo -e "${GN}The process is complete, and the containers have been successfully updated.${CL}\n"
fi
if [ "${#containers_needing_reboot[@]}" -gt 0 ]; then
  echo -e "${RD}The following containers require a reboot:${CL}"
  for container_name in "${containers_needing_reboot[@]}"; do
    echo "$container_name"
  done

  REBOOT_CHOICE="no"
  if [[ -n "$var_auto_reboot" ]]; then
    REBOOT_CHOICE="$var_auto_reboot"
  else
    echo -ne "${INFO} Do you wish to reboot these containers? <yes/No>  "
    read -r prompt
    if [[ ${prompt,,} =~ ^(yes)$ ]]; then
      REBOOT_CHOICE="yes"
    fi
  fi

  if [[ "$REBOOT_CHOICE" == "yes" ]]; then
    echo -e "${CROSS}${HOLD} ${YWB}Rebooting containers.${CL}"
    for container_name in "${containers_needing_reboot[@]}"; do
      container=$(echo $container_name | cut -d " " -f 1)
      pct reboot ${container}
    done
  fi
fi
exit_batch_update "$normal_result"
