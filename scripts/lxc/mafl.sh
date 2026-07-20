#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://mafl.hywax.space/

APP="Mafl"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

  fetch_and_deploy_gh_release "mafl" "hywax/mafl" "tarball"

  msg_info "Installing Mafl"
  mkdir -p /opt/mafl/data
  curl -fsSL "https://raw.githubusercontent.com/hywax/mafl/main/.example/config.yml" -o "/opt/mafl/data/config.yml"
  cd /opt/mafl || exit
  export NUXT_TELEMETRY_DISABLED=true
  $STD yarn install
  $STD yarn build
  msg_ok "Installed Mafl"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mafl.service
[Unit]
Description=Mafl
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
WorkingDirectory=/opt/mafl/
ExecStart=yarn preview

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mafl
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
  if [[ ! -d /opt/mafl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "mafl" "hywax/mafl"; then
    msg_info "Stopping Service"
    systemctl stop mafl
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    mkdir -p /opt/mafl-backup/data
    mv /opt/mafl/data /opt/mafl-backup/data
    rm -rf /opt/mafl
    msg_ok "Backup complete"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mafl" "hywax/mafl" "tarball"

    msg_info "Updating Mafl"
    cd /opt/mafl || exit
    $STD yarn install
    $STD yarn build
    mv /opt/mafl-backup/data /opt/mafl/data
    msg_ok "Updated Mafl"

    msg_info "Starting Service"
    systemctl start mafl
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
