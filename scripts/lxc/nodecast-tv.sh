#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: luismco
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/technomancer702/nodecast-tv

APP="nodecast-tv"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  fetch_and_deploy_gh_release "nodecast-tv" "technomancer702/nodecast-tv" "tarball"
  NODE_VERSION="20" setup_nodejs

  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  msg_info "Installing Modules"
  cd /opt/nodecast-tv || exit
  $STD npm install
  msg_ok "Installed Modules"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/nodecast-tv.service
[Unit]
Description=nodecast-tv
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/opt/nodecast-tv
ExecStart=/bin/npm run dev
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nodecast-tv
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/nodecast-tv ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nodecast-tv" "technomancer702/nodecast-tv"; then
    msg_info "Stopping Service"
    systemctl stop nodecast-tv
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "nodecast-tv" "technomancer702/nodecast-tv" "tarball"

    msg_info "Updating Modules"
    cd /opt/nodecast-tv || exit
    $STD npm install
    msg_ok "Updated Modules"

    msg_info "Starting Service"
    systemctl start nodecast-tv
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
