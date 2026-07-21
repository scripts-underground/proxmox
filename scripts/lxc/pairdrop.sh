#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://pairdrop.net/ | Github: https://github.com/schlagmichdoch/PairDrop
# shellcheck disable=SC2034

APP="PairDrop"
var_tags="${var_tags:-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "pairdrop" "schlagmichdoch/PairDrop" "tarball"

  msg_info "Configuring PairDrop"
  cd /opt/pairdrop || exit
  $STD npm install
  msg_ok "Configured PairDrop"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pairdrop.service
[Unit]
Description=PairDrop Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=npm start
WorkingDirectory=/opt/pairdrop
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pairdrop
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/pairdrop ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "pairdrop" "schlagmichdoch/PairDrop"; then
    msg_info "Stopping Service"
    systemctl stop pairdrop
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "pairdrop" "schlagmichdoch/PairDrop" "tarball"

    msg_info "Configuring PairDrop"
    cd /opt/pairdrop || exit
    $STD npm install
    msg_ok "Configured PairDrop"

    msg_info "Starting Service"
    systemctl start pairdrop
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
