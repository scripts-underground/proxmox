#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/sbondCo/Watcharr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Watcharr"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y gcc
  msg_ok "Installed Dependencies"

  setup_go
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "watcharr" "sbondCo/Watcharr" "tarball"

  msg_info "Setup Watcharr"
  cd /opt/watcharr || exit
  $STD npm i
  $STD npm run build
  mv ./build ./server/ui
  cd server || exit
  export CGO_ENABLED=1 GOOS=linux
  $STD go mod download
  $STD go build -o ./watcharr
  msg_ok "Setup Watcharr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/watcharr.service
[Unit]
Description=Watcharr Service
After=network.target

[Service]
WorkingDirectory=/opt/watcharr/server
ExecStart=/opt/watcharr/server/watcharr
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now watcharr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/watcharr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "watcharr" "sbondCo/Watcharr"; then
    msg_info "Stopping Service"
    systemctl stop watcharr
    msg_ok "Stopped Service"

    create_backup /opt/watcharr/server/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "watcharr" "sbondCo/Watcharr" "tarball"
    restore_backup

    msg_info "Updating Watcharr"
    cd /opt/watcharr || exit
    export GOOS=linux
    $STD npm i
    $STD npm run build
    mv ./build ./server/ui
    cd server || exit
    $STD go mod download
    $STD go build -o ./watcharr
    msg_ok "Updated Watcharr"

    msg_info "Starting Service"
    systemctl start watcharr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
