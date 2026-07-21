#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://whodb.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="WhoDB"
var_tags="${var_tags:-database;management;gui}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "whodb" "clidey/whodb" "singlefile" "latest" "/opt/whodb" "whodb-*-linux-$(get_system_arch)"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/whodb.service
[Unit]
Description=WhoDB Database Management
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/whodb
ExecStart=/opt/whodb/whodb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now whodb
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/whodb/whodb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "whodb" "clidey/whodb"; then
    msg_info "Stopping Service"
    systemctl stop whodb
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "whodb" "clidey/whodb" "singlefile" "latest" "/opt/whodb" "whodb-*-linux-$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start whodb
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
