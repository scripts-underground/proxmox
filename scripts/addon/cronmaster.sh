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
var_addon_config_path="${var_addon_config_path:-/opt/cronmaster/.env}"
var_addon_service_path="${var_addon_service_path:-/etc/systemd/system/cronmaster.service}"
var_addon_service="${var_addon_service:-cronmaster}"
var_addon_repo="${var_addon_repo:-fccview/cronmaster}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/cronmaster_backup}"
var_addon_creds_path="${var_addon_creds_path:-/root/cronmaster.creds}"
var_addon_default_port="${var_addon_default_port:-3000}"

function header_info() {
  clear
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
  cat << EOF > "$var_addon_config_path"
NODE_ENV=production
AUTH_PASSWORD=${AUTH_PASS}
PORT=${var_addon_default_port}
HOSTNAME=0.0.0.0
NEXT_TELEMETRY_DISABLED=1
EOF
  chmod 600 "$var_addon_config_path"
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
  cat << EOF > "$var_addon_creds_path"
CronMaster Credentials
======================
Password: ${AUTH_PASS}

Web UI: http://${LOCAL_IP}:${var_addon_default_port}
EOF
  chmod 600 "$var_addon_creds_path"
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
  if check_for_gh_release "cronmaster" "$var_addon_repo"; then
    msg_info "Stopping service"
    systemctl stop "$var_addon_service" &> /dev/null || true
    msg_ok "Stopped service"

    msg_info "Backing up configuration"
    mkdir -p "$var_addon_backup_dir"
    cp "$var_addon_config_path" "$var_addon_backup_dir/env.bak" 2> /dev/null || true
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cronmaster" "$var_addon_repo" "prebuild" "latest" "$var_addon_install_path" "cronmaster_*_prebuild.tar.gz"

    msg_info "Restoring configuration"
    cp "$var_addon_backup_dir/env.bak" "$var_addon_config_path" 2> /dev/null || true
    rm -rf "$var_addon_backup_dir"
    msg_ok "Restored configuration"

    msg_info "Starting service"
    systemctl start "$var_addon_service"
    msg_ok "Started service"
    msg_ok "Updated successfully"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now "$var_addon_service" &> /dev/null || true
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
