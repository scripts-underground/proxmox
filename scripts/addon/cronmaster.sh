#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/fccview/cronmaster

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CronMaster"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/cronmaster}"
var_addon_config_path="${var_addon_config_path:-${var_addon_install_path}/.env}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/cronmaster.service}"
var_addon_service="${var_addon_service:-cronmaster}"
var_addon_repo="${var_addon_repo:-fccview/cronmaster}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/cronmaster_backup}"
var_addon_creds_path="${var_addon_creds_path:-/root/cronmaster.creds}"
var_addon_default_port="${var_addon_default_port:-3000}"

function header_info() {
  terminal_clear
  cat << "EOF"
   ______                __  ___           __
  / ____/________  ____ /  |/  /___ ______/ /____  _____
 / /   / ___/ __ \/ __ \/ /|_/ / __ `/ ___/ __/ _ \/ ___/
/ /___/ /  / /_/ / / / / /  / / /_/ (__  ) /_/  __/ /
\____/_/   \____/_/ /_/_/  /_/\__,_/____/\__/\___/_/

EOF
}

function install_script() {
  [[ "$OS_FAMILY" == "debian" ]] || {
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  }

  if command -v node &> /dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="22" setup_nodejs
  fi

  fetch_and_deploy_gh_release "cronmaster" "$var_addon_repo" "prebuild" "latest" "$var_addon_install_path" "cronmaster_*_prebuild.tar.gz"

  local AUTH_PASS
  AUTH_PASS="$(openssl rand -base64 18 | cut -c1-13)"

  msg_info "Creating configuration"
  addon_write_private_file "$var_addon_config_path" << EOF
NODE_ENV=production
AUTH_PASSWORD=${AUTH_PASS}
PORT=${var_addon_default_port}
HOSTNAME=0.0.0.0
NEXT_TELEMETRY_DISABLED=1
EOF
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat << EOF > "$var_addon_service_path"
[Unit]
Description=CronMaster Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${var_addon_install_path}
EnvironmentFile=${var_addon_config_path}
ExecStart=/usr/bin/node ${var_addon_install_path}/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$var_addon_service"
  msg_ok "Created and started service"

  msg_info "Saving credentials"
  addon_write_private_file "$var_addon_creds_path" << EOF
CronMaster Credentials
======================
Password: ${AUTH_PASS}

Web UI: http://${LOCAL_IP}:${var_addon_default_port}
EOF
  msg_ok "Saved credentials to ${var_addon_creds_path}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  msg_ok "Credentials saved to: ${BL}${var_addon_creds_path}${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
  echo ""
}

function update_script() {
  if check_for_gh_release "cronmaster" "$var_addon_repo" "${var_appversion:-}"; then
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
    addon_keep_inputs CLEAN_INSTALL_KEEP_PATHS "$var_addon_install_path" "$var_addon_config_path" || return $?
    local was_running=0 update_status=0 before after
    # A failed publisher is not proof of a complete rollback. Include the whole
    # Node runtime, configuration and effective unit before admitting recovery.
    function cronmaster_state() (
      addon_runtime_fingerprint --tree "$var_addon_install_path" --file "$var_addon_config_path" --unit "$var_addon_service"
    )
    before=$(cronmaster_state) || before=unverified
    addon_service_begin "$var_addon_service" was_running || return $?
    msg_info "Stopping service"
    systemctl stop "$var_addon_service" || update_status=$?
    if [[ "$update_status" == 0 ]]; then
      msg_ok "Stopped service"
      addon_backup_create "$var_addon_backup_dir" "$var_addon_config_path" || update_status=$?
      if [[ "$update_status" == 0 ]]; then
        CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cronmaster" "$var_addon_repo" "prebuild" "${CHECK_UPDATE_RELEASE:-latest}" "$var_addon_install_path" "cronmaster_*_prebuild.tar.gz" || update_status=$?
      fi
    fi
    if [[ "$update_status" != 0 ]]; then
      after=$(cronmaster_state) || after=unverified
      if [[ "$before" != unverified && "$after" == "$before" && "$was_running" == 1 ]]; then
        systemctl start "$var_addon_service" || msg_warn "Unable to restart previous CronMaster service"
      elif [[ "$after" != "$before" ]]; then
        msg_warn "Previous CronMaster installation is unverified; service stays stopped"
      fi
      return "$update_status"
    fi
    if [[ "$was_running" == 1 ]]; then
      msg_info "Starting service"
      addon_service_complete "$var_addon_service" || return $?
      msg_ok "Started service"
    fi
    addon_backup_complete "$var_addon_backup_dir" || return $?
    msg_ok "Updated successfully"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  svc_prepare_uninstall "$var_addon_service"
  rm -f "$var_addon_service_path"
  rm -rf "$var_addon_install_path"
  rm -f "$HOME/.cronmaster"
  rm -f "$var_addon_creds_path"
  msg_ok "${APP} has been uninstalled"
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id cronmaster -- "$@"
