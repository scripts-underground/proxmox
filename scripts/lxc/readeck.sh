#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://readeck.org/en/

# shellcheck disable=SC2034
APP="Readeck"
var_tags="${var_tags:-bookmark}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_codeberg_release "readeck" "readeck/readeck" "singlefile" "latest" "/opt/readeck" "readeck-*-linux-$(get_system_arch)"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/readeck.service
[Unit]
Description=Readeck Service
After=network.target

[Service]
Environment=READECK_SERVER_HOST=0.0.0.0
Environment=READECK_SERVER_PORT=8000
ExecStart=/opt/readeck/./readeck serve
WorkingDirectory=/opt/readeck
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now readeck
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/readeck ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_codeberg_release "readeck" "readeck/readeck"; then
    msg_info "Stopping Service"
    systemctl stop readeck
    msg_ok "Stopped Service"

    fetch_and_deploy_codeberg_release "readeck" "readeck/readeck" "singlefile" "latest" "/opt/readeck" "readeck-*-linux-$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start readeck
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
