#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://overseerr.dev/

APP="Overseerr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3 build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "overseerr" "sct/overseerr" "tarball"

  msg_info "Installing ${APP} (Patience)"
  cd /opt/overseerr || exit
  $STD yarn install
  $STD yarn build
  msg_ok "Installed ${APP}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/overseerr.service
[Unit]
Description=Overseerr Service
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/overseerr
ExecStart=/usr/bin/yarn start

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now overseerr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5055${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/overseerr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "overseerr" "sct/overseerr"; then
    msg_info "Stopping Service"
    systemctl stop overseerr
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    mv /opt/overseerr/config /opt/config_backup
    msg_ok "Backup Created"

    NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
    fetch_and_deploy_gh_release "overseerr" "sct/overseerr" "tarball"
    rm -rf /opt/overseerr/config

    msg_info "Configuring ${APP} (Patience)"
    cd /opt/overseerr || exit
    $STD yarn install
    $STD yarn build
    mv /opt/config_backup /opt/overseerr/config
    msg_ok "Configured ${APP}"

    msg_info "Starting Service"
    systemctl start overseerr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
