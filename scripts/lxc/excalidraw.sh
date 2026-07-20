#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/excalidraw/excalidraw

APP="Excalidraw"
var_tags="${var_tags:-diagrams}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y xdg-utils
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "excalidraw" "excalidraw/excalidraw" "tarball"

  msg_info "Configuring Excalidraw"
  cd /opt/excalidraw || exit
  $STD yarn config set ignore-engines true
  $STD yarn
  msg_ok "Setup Excalidraw"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/excalidraw.service
[Unit]
Description=Excalidraw Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/excalidraw
ExecStart=/usr/bin/yarn start --host
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now excalidraw
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/excalidraw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

  if check_for_gh_release "excalidraw" "excalidraw/excalidraw"; then
    msg_info "Stopping Service"
    systemctl stop excalidraw
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "excalidraw" "excalidraw/excalidraw" "tarball"

    msg_info "Updating Excalidraw"
    cd /opt/excalidraw || exit
    $STD yarn config set ignore-engines true
    $STD yarn
    msg_ok "Updated Excalidraw"

    msg_info "Starting Service"
    systemctl start excalidraw
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
