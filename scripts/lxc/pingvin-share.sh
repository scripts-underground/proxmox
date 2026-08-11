#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/stonith404/pingvin-share

# shellcheck disable=SC2034
APP="Pingvin Share"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-stonith404/pingvin-share}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing Pingvin Share"
  fetch_and_deploy_gh_release "pingvin-share" "$var_lxc_git_repo" "tarball"
  cd /opt/pingvin-share || exit

  mkdir -p /opt/pingvin-share/data
  cat << EOF > /opt/pingvin-share/.env
DATABASE_URL=file:./data/pingvin-share.db
PORT=80
EOF

  $STD npm install
  $STD npm run build
  msg_ok "Installed Pingvin Share"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pingvin-share.service
[Unit]
Description=Pingvin Share
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pingvin-share
EnvironmentFile=/opt/pingvin-share/.env
ExecStart=/usr/bin/node /opt/pingvin-share/backend/dist/main.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pingvin-share
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pingvin-share ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pingvin-share" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop pingvin-share
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pingvin-share" "$var_lxc_git_repo" "tarball"
    cd /opt/pingvin-share || exit
    $STD npm install
    $STD npm run build
    systemctl start pingvin-share
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
