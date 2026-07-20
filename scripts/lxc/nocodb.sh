#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.nocodb.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NocoDB"
var_tags="${var_tags:-nocodb;database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  local nocodb_arch
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    nocodb_arch="arm64"
  else
    nocodb_arch="x64"
  fi
  fetch_and_deploy_gh_release "nocodb" "nocodb/nocodb" "singlefile" "latest" "/opt/nocodb/" "Noco-linux-${nocodb_arch}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/nocodb.service
[Unit]
Description=NocoDB
After=network.target

[Service]
Type=simple
Restart=always
User=root
WorkingDirectory=/opt/nocodb
ExecStart=/opt/nocodb/nocodb

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nocodb
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/dashboard${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/nocodb.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "nocodb" "nocodb/nocodb"; then
    msg_info "Stopping Service"
    systemctl stop nocodb
    msg_ok "Stopped Service"

    local nocodb_arch
    if [[ "$(get_system_arch)" == "arm64" ]]; then
      nocodb_arch="arm64"
    else
      nocodb_arch="x64"
    fi
    fetch_and_deploy_gh_release "nocodb" "nocodb/nocodb" "singlefile" "latest" "/opt/nocodb/" "Noco-linux-${nocodb_arch}"

    msg_info "Starting Service"
    systemctl start nocodb
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
