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

# Parser operation is a closed literal mode, separate from all identity data.
# Selection requires one new owned volume, not the newest matching filename.
function backup_inventory_volid() {
  perl -MJSON -e '
use strict; use warnings;
my $mode = shift @ARGV;
eval {
    my %arity = ("inventory" => 3, "select-new" => 5, "verify-exact" => 5);
    die "invalid parser mode/arity" unless defined($mode) && exists($arity{$mode}) && @ARGV == $arity{$mode};
    my ($before, $after, $store, $ct, $notes, $expected);
    if ($mode eq "inventory") {
        ($before, $store, $ct) = @ARGV; $after = $before;
    } elsif ($mode eq "select-new") {
        ($before, $after, $store, $ct, $notes) = @ARGV;
    } else {
        ($before, $store, $ct, $notes, $expected) = @ARGV; $after = $before;
    }
    my $load = sub {
        my ($path) = @_;
        open my $fh, "<", $path or die "cannot read inventory: $!";
        local $/; my $data = decode_json(<$fh>); close $fh or die "inventory close: $!";
        die "inventory is not an array" unless ref($data) eq "ARRAY";
        my %rows;
        for my $row (@$data) {
            die "invalid inventory row" unless ref($row) eq "HASH";
            for my $key (qw(volid vmid format content subtype)) {
                die "missing/scalar inventory field $key" unless defined($row->{$key}) && !ref($row->{$key});
            }
            my $id = $row->{volid};
            die "foreign or malformed volume" unless index($id, "$store:backup/") == 0 && $id !~ /[\s\x00-\x1f\x7f]/;
            die "foreign CT/content" unless $row->{vmid} =~ /\A[1-9][0-9]*\z/ && $row->{vmid} eq $ct && $row->{content} eq "backup";
            die "duplicate volume" if exists($rows{$id});
            $rows{$id} = $row;
        }
        return \%rows;
    };
    my $old = $load->($before); my $new = $load->($after);
    exit 0 if $mode eq "inventory";
    my @ids = $mode eq "select-new" ? (grep { !exists($old->{$_}) } keys %$new) : ($expected);
    die "expected exactly one newly created backup" unless @ids == 1;
    my $id = $ids[0]; my $row = $new->{$id};
    die "missing/foreign producer receipt" unless $row && $row->{subtype} eq "lxc" && defined($row->{notes}) && !ref($row->{notes}) && $row->{notes} eq $notes;
    my $file = $id =~ /\A\Q$store\E:backup\/vzdump-lxc-\Q$ct\E-[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{2}_[0-9]{2}_[0-9]{2}\.tar\.zst\z/ && $row->{format} eq "tar.zst";
    my $pbs = $id =~ /\A\Q$store\E:backup\/ct\/\Q$ct\E\/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/ && $row->{format} eq "pbs-ct";
    die "wrong CT backup type" unless $file || $pbs;
    print $id;
};
if ($@) { print STDERR "Invalid backup receipt: $@\n"; exit 65; }
' -- "$@"
}

function read_backup_inventory() {
  pvesh get "/nodes/$NODE/storage/$1/content" --content backup --vmid "$2" --output-format json
}

function create_backup_receipt() {
  local _cb_ct=$1 _cb_store=$2 _cb_stage=$3 _cb_notes=$4
  read_backup_inventory "$_cb_store" "$_cb_ct" > "$_cb_stage/before" || return $?
  backup_inventory_volid inventory "$_cb_stage/before" "$_cb_store" "$_cb_ct" > /dev/null || return $?
  vzdump "$_cb_ct" --compress zstd --storage "$_cb_store" --notes-template "$_cb_notes" > "$_cb_stage/vzdump.log" 2>&1 || return $?
  read_backup_inventory "$_cb_store" "$_cb_ct" > "$_cb_stage/after" || return $?
  backup_inventory_volid select-new "$_cb_stage/before" "$_cb_stage/after" "$_cb_store" "$_cb_ct" "$_cb_notes"
}

function revalidate_backup_receipt() {
  local _vr_ct=$1 _vr_stage _vr_status=0 _vr_cleanup
  [[ "${batch_backup_ct:-}" == "$_vr_ct" && "${batch_backup_store:-}" == "$STORAGE_CHOICE" &&
    -n "${batch_backup_volid:-}" && -n "${batch_backup_notes:-}" ]] || return 65
  _vr_stage=$(mktemp -d "${TMPDIR:-/tmp}/update-apps-receipt.XXXXXXXX") || return $?
  read_backup_inventory "$batch_backup_store" "$_vr_ct" > "$_vr_stage/current" || _vr_status=$?
  if [[ "$_vr_status" == 0 ]]; then
    backup_inventory_volid verify-exact "$_vr_stage/current" "$batch_backup_store" "$_vr_ct" "$batch_backup_notes" "$batch_backup_volid" > /dev/null || _vr_status=$?
  fi
  if rm -rf -- "$_vr_stage"; then :; else
    _vr_cleanup=$?
    [[ "$_vr_status" != 0 ]] || _vr_status=$_vr_cleanup
  fi
  return "$_vr_status"
}

function read_batch_state() {
  local _rs_state
  _rs_state=$(pct status "$1") || return $?
  case "$_rs_state" in
    'status: running') printf running ;;
    'status: stopped') printf stopped ;;
    *)
      printf 'Unknown state for container %s: %s\n' "$1" "$_rs_state" >&2
      return 69
      ;;
  esac
}

# Recovery consumes only this run's receipt, with checked ordered power effects.
function restore_container_backup() {
  local _rb_ct=$1 _rb_config _rb_storage _rb_status _rb_state
  if revalidate_backup_receipt "$_rb_ct"; then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at receipt (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
  if _rb_state=$(read_batch_state "$_rb_ct"); then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at state (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
  if [[ "$_rb_state" == running ]]; then
    if pct stop "$_rb_ct"; then :; else
      _rb_status=$?
      printf 'Container %s backup recovery failed at stop (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
      return "$_rb_status"
    fi
    if _rb_state=$(read_batch_state "$_rb_ct"); then :; else
      _rb_status=$?
      printf 'Container %s backup recovery failed at state (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
      return "$_rb_status"
    fi
    [[ "$_rb_state" == stopped ]] || {
      printf 'Container %s backup recovery failed at stopped readback (status 69).\n' "$_rb_ct" >&2
      return 69
    }
  fi
  if _rb_config=$(pct config "$_rb_ct"); then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at config (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
  if _rb_storage=$(awk -F '[:,]' '/^rootfs:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; found++} END {if (found != 1) exit 65}' <<< "$_rb_config"); then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at storage (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
  if [[ -z "$_rb_storage" ]]; then
    printf 'Container %s backup recovery failed at storage (status 65); inspect actual state.\n' "$_rb_ct" >&2
    return 65
  fi
  if pct restore "$_rb_ct" "$batch_backup_volid" --storage "$_rb_storage" --force > /dev/null 2>&1; then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at restore (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
  if pct start "$_rb_ct"; then :; else
    _rb_status=$?
    printf 'Container %s backup recovery failed at start (status %s); inspect actual state.\n' "$_rb_ct" "$_rb_status" >&2
    return "$_rb_status"
  fi
}

function detect_service() {
  service='' source_script_id=''
  local LC_ALL=C _ds_stage _ds_text='' _ds_line='' _ds_result='' _ds_status=0 _ds_cleanup=0
  local _ds_baked=0 _ds_bad=0 _ds_legacy=0 _ds_other=0 _ds_legacy_name=''
  local _ds_identity='' _ds_identity_count=0 _ds_identity_bad=0
  local _ds_identity_re='^declare -- LXC_SCRIPT_ID=([a-z0-9][a-z0-9._-]{0,63})$'
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
          "$_ds_line" =~ [[:space:]]LXC_SCRIPT_ID([[:space:]]|\+?=|\[|$) ]] || [[ "$_ds_line" =~ ^[[:space:]]*LXC_SCRIPT_ID([[:space:]]*\+?=|\[) ]]; then
          _ds_identity_count=$((_ds_identity_count + 1))
          if [[ "$_ds_line" =~ $_ds_identity_re && "${BASH_REMATCH[1]}" != *.sh ]]; then
            _ds_identity=${BASH_REMATCH[1]}
          else
            _ds_identity_bad=1
          fi
          _ds_other=1
        elif [[ "$_ds_line" =~ ^[[:space:]]*(declare|export|readonly)[[:space:]] &&
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
        [[ "$_ds_identity_count" == 1 && "$_ds_identity_bad" == 0 ]] || _ds_identity=''
      elif [[ "$_ds_legacy" == 1 && "$_ds_other" == 0 ]]; then
        _ds_result=$_ds_legacy_name
        _ds_identity=$_ds_legacy_name
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
    source_script_id=$_ds_identity
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
  if [[ -z "${source_script_id:-}" ]]; then
    printf 'Warning: source-script identity is unknown for container %s; requirements are unknown.\n' "$container" >&2
  elif _ba_script=$(curl -fsSL "$REPO_BASE/scripts/lxc/${source_script_id}.sh"); then
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

# Only a successfully owned start may be restored on refusal or after an outcome.
function restore_batch_start() {
  local _bs_state
  [[ "$batch_started" == 1 ]] || return 0
  _bs_state=$(read_batch_state "$container") || return $?
  [[ "$_bs_state" != stopped ]] || return 0
  printf 'Restoring batch-started container %s to stopped state.\n' "$container" >&2
  pct shutdown "$container" --timeout 60 || return $?
  _bs_state=$(read_batch_state "$container") || return $?
  [[ "$_bs_state" == stopped ]] || return 69
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
  local _bc_ct=$1 _bc_store=$STORAGE_CHOICE _bc_stage _bc_token='' _bc_notes _bc_volid _bc_status=0 _bc_cleanup
  batch_backup_ct='' batch_backup_store='' batch_backup_notes='' batch_backup_volid=''
  msg_info "Creating backup for container $1"
  _bc_stage=$(mktemp -d "${TMPDIR:-/tmp}/update-apps-backup.XXXXXXXX") || _bc_status=$?
  if [[ "$_bc_status" == 0 ]]; then
    IFS= read -r _bc_token < /proc/sys/kernel/random/uuid || _bc_status=$?
    _bc_notes="scripts-underground backup updater ct=$_bc_ct receipt=$_bc_token"
    if [[ "$_bc_status" == 0 ]]; then
      _bc_volid=$(create_backup_receipt "$_bc_ct" "$_bc_store" "$_bc_stage" "$_bc_notes") || _bc_status=$?
    fi
    if rm -rf -- "$_bc_stage"; then :; else
      _bc_cleanup=$?
      [[ "$_bc_status" != 0 ]] || _bc_status=$_bc_cleanup
    fi
  fi
  if [[ "$_bc_status" != 0 ]]; then
    msg_error "Backup failed for container $1 (status $_bc_status)"
    exit_batch_update 1 abort
  fi
  batch_backup_ct=$_bc_ct batch_backup_store=$_bc_store batch_backup_notes=$_bc_notes batch_backup_volid=$_bc_volid
  msg_ok "Backup created"
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
  batch_backup_ct='' batch_backup_store='' batch_backup_notes='' batch_backup_volid=''
  abort_after_cleanup=0
  echo -e "${BL}[INFO]${CL} Updating container $container"

  if [ "$BACKUP_CHOICE" == "yes" ]; then
    backup_container $container
  fi

  config=$(pct config "$container") || admission_status=$?
  os=$(awk '/^ostype/ {print $2}' <<< "$config")
  status=$(read_batch_state "$container") || admission_status=$?
  template=false
  [[ "$config" != *'template:'* ]] || template=true
  if [[ "$admission_status" == 0 && "$template" == false && "$status" == stopped ]]; then
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
    if restore_container_backup "$container"; then
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
    abort_after_cleanup=1
  fi
  if restore_batch_start; then :; else
    cleanup_status=$?
    printf 'Container %s: unable to restore batch-owned start (status %s); inspect its actual state.\n' "$container" "$cleanup_status" >&2
    exit_batch_update 1 abort
  fi
  [[ "$abort_after_cleanup" != 1 ]] || exit_batch_update 1 abort
done
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
