#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/dragonflydb/dragonfly

# shellcheck disable=SC2034
APP="Dragonfly"
var_tags="${var_tags:-database;cache}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  local version dropin runtime config path stage password password_status
  version=$(systemctl --version)
  version=${version#systemd }
  version=${version%% *}
  if [[ ! "$version" =~ ^[0-9]+$ ]] || ((version < 257)); then
    msg_error "Dragonfly requires systemd 257 or newer for isolated temporary directories"
    return 65
  fi
  dropin=/etc/systemd/system/dragonfly.service.d/scripts-underground.conf
  runtime=/etc/dragonfly/scripts-underground-runtime.env
  config=/etc/dragonfly/dragonfly.conf
  for path in /etc/dragonfly /etc/systemd/system/dragonfly.service.d "$dropin" "$runtime" "$config"; do
    if [[ -L "$path" || (-e "$path" && ! -d "$path" && ! -f "$path") ]]; then
      msg_error "Unexpected Dragonfly configuration path: $path"
      return 65
    fi
  done
  mkdir -p /etc/dragonfly /etc/systemd/system/dragonfly.service.d
  local unit='[Unit]
ConditionPathExists=/etc/dragonfly/scripts-underground-runtime.env

[Service]
EnvironmentFile=/etc/dragonfly/scripts-underground-runtime.env
PrivateTmp=disconnected
ReadOnlyPaths=/tmp /var/tmp
'
  local environment='TMPDIR=/var/lib/dragonfly/tmp
'
  # Refuse a collision rather than replacing an operator's unit or runtime input.
  if [[ -e "$dropin" ]]; then
    if ! cmp -s "$dropin" <(printf '%s' "$unit"); then
      msg_error "Unexpected Dragonfly drop-in: $dropin"
      return 65
    fi
  else
    stage=$(mktemp /etc/systemd/system/dragonfly.service.d/.scripts-underground.XXXXXXXX)
    printf '%s' "$unit" > "$stage"
    chmod 0644 "$stage"
    mv -T "$stage" "$dropin"
  fi
  if [[ -e "$runtime" ]]; then
    if ! cmp -s "$runtime" <(printf '%s' "$environment") || [[ ! -f "$config" ]] || ! grep -qE '^--requirepass=.+$' "$config"; then
      msg_error "Incomplete or unexpected Dragonfly runtime configuration: $runtime"
      return 65
    fi
  fi
  # The vendor package attempts first startup in postinst. Its real required
  # environment file is absent until authenticated disk-backed configuration is ready.
  $STD systemctl daemon-reload
  msg_info "Installing Dependencies"
  $STD apt install -y openssl redis-tools
  msg_ok "Installed Dependencies"
  DPKG_FORCE_CONFOLD=1 fetch_and_deploy_gh_release "dragonfly" "dragonflydb/dragonfly" "binary" "latest" "" "dragonfly_$(get_system_arch).deb"

  msg_info "Configuring Dragonfly"
  path=/var/lib/dragonfly/tmp
  if [[ -L "$path" || (-e "$path" && ! -d "$path") ]]; then
    msg_error "Unexpected Dragonfly data path: $path"
    return 65
  fi
  if [[ ! -d "$path" ]]; then
    install -d -o dfly -g dfly -m 0700 "$path"
  fi
  # A retry completes missing settings, retaining any existing password/data.
  if ! grep -qE '^--requirepass=.+$' "$config"; then
    if password=$(openssl rand -hex 32); then
      if [[ ! "$password" =~ ^[0-9a-f]{64}$ ]]; then
        msg_error "OpenSSL returned an invalid Dragonfly password"
        return 65
      fi
    else
      password_status=$?
      msg_error "Failed to generate the Dragonfly password"
      return "$password_status"
    fi
    printf '\n--requirepass=%s\n' "$password" >> "$config"
  fi
  local setting
  for setting in 'bind=0.0.0.0' 'port=6379' 'dbfilename=dump' 'snapshot_cron=*/30 * * * *'; do
    if ! grep -qE "^--${setting%%=*}=" "$config"; then
      printf -- '--%s\n' "$setting" >> "$config"
    fi
  done
  # Source declarations can describe unlinked library/test facilities. Check the
  # installed server's actual static CLI before releasing the runtime-file gate.
  local capabilities capability_status flag_line flag_name
  local -A supported_flags=()
  capabilities=$(mktemp -d "${TMPDIR}/dragonfly-capabilities.XXXXXXXX")
  if timeout 15s /usr/bin/dragonfly --helpfull > "$capabilities/help" 2> "$capabilities/error"; then
    capability_status=0
  else
    capability_status=$?
  fi
  if [[ "$capability_status" != 1 || -s "$capabilities/error" ]] || ! grep -Fxq 'dragonfly: a modern in-memory store.' "$capabilities/help" || ! grep -Fxq 'Usage: dragonfly [FLAGS]' "$capabilities/help"; then
    rm -rf -- "$capabilities"
    msg_error "Unable to validate the installed Dragonfly CLI capabilities"
    [[ "$capability_status" == 0 || "$capability_status" == 1 ]] && return 65
    return "$capability_status"
  fi
  sed -nE 's/^    --([A-Za-z0-9_]+)[[:space:]].*/\1/p' "$capabilities/help" > "$capabilities/flags"
  if [[ ! -s "$capabilities/flags" ]]; then
    rm -rf -- "$capabilities"
    msg_error "Empty Dragonfly CLI capability inventory"
    return 65
  fi
  while IFS= read -r flag_name; do
    if [[ -n "${supported_flags[$flag_name]+present}" ]]; then
      rm -rf -- "$capabilities"
      msg_error "Invalid Dragonfly CLI capability inventory"
      return 65
    fi
    supported_flags["$flag_name"]=1
  done < "$capabilities/flags"
  while IFS= read -r flag_line || [[ -n "$flag_line" ]]; do
    flag_line="${flag_line#"${flag_line%%[![:space:]]*}"}"
    case "$flag_line" in '' | '#'*) continue ;; esac
    if [[ "$flag_line" =~ ^--([A-Za-z0-9_]+)(=|[[:space:]]|$) ]]; then
      flag_name=${BASH_REMATCH[1]}
      if [[ -n "${supported_flags[$flag_name]+present}" ]]; then
        continue
      fi
    fi
    rm -rf -- "$capabilities"
    msg_error "Dragonfly configuration contains an unsupported or malformed flag"
    return 65
  done < "$config"
  rm -rf -- "$capabilities"
  # Publish actual runtime configuration last, on the destination filesystem.
  if [[ ! -e "$runtime" ]]; then
    stage=$(mktemp /etc/dragonfly/.scripts-underground-runtime.XXXXXXXX)
    printf '%s' "$environment" > "$stage"
    chown root:dfly "$stage"
    chmod 0640 "$stage"
    mv -T "$stage" "$runtime"
  fi
  msg_ok "Configured Dragonfly"
  msg_info "Starting Dragonfly"
  $STD systemctl daemon-reload
  systemctl enable -q --now dragonfly
  msg_ok "Started Dragonfly"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}The password is --requirepass in /etc/dragonfly/dragonfly.conf inside the container.${CL}"
  echo -e "${GATEWAY}${BGN}redis-cli -h ${IP} -p 6379 --askpass${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/dragonfly ]]; then
    msg_error "No Dragonfly Installation Found!"
    return 1
  fi
  if check_for_gh_release "dragonfly" "dragonflydb/dragonfly"; then
    msg_info "Stopping Dragonfly"
    systemctl stop dragonfly
    msg_ok "Stopped Dragonfly"
    DPKG_FORCE_CONFOLD=1 fetch_and_deploy_gh_release "dragonfly" "dragonflydb/dragonfly" "binary" "latest" "" "dragonfly_$(get_system_arch).deb"
    msg_info "Starting Dragonfly"
    $STD systemctl daemon-reload
    systemctl start dragonfly
    msg_ok "Started Dragonfly"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
