#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AminGholizad (AminGholizad)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/PanSalut/Koffan

# shellcheck disable=SC2034
APP="Koffan"
var_tags="${var_tags:-productivity}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  setup_go
  fetch_and_deploy_gh_release "koffan" "PanSalut/Koffan" "tarball"

  msg_info "Building Koffan"
  cd /opt/koffan || exit
  $STD go build -o koffan main.go
  msg_ok "Built Koffan"

  msg_info "Configuring Koffan"
  APP_PASSWD=$(openssl rand -base64 12)
  mkdir /opt/koffan/data
  cat << EOF > /opt/koffan/data/.env
APP_ENV=production
APP_PASSWORD=${APP_PASSWD}
PORT=3000
DB_PATH=/opt/koffan/data/shopping.db
EOF
  cat << EOF > ~/koffan.creds
Password: ${APP_PASSWD}
EOF
  msg_ok "Configured Koffan"

  msg_info "Creating systemd service"
  cat << EOF > /etc/systemd/system/koffan.service
[Unit]
Description=Koffan Service
After=network.target

[Service]
EnvironmentFile=/opt/koffan/data/.env
WorkingDirectory=/opt/koffan
ExecStart=/opt/koffan/koffan
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now koffan
  msg_ok "Created systemd service"
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

  if [[ ! -f /opt/koffan/koffan ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "koffan" "PanSalut/Koffan"; then
    msg_info "Stopping Service"
    systemctl stop koffan
    msg_ok "Stopped Service"

    create_backup /opt/koffan/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "koffan" "PanSalut/Koffan" "tarball"
    restore_backup

    msg_info "Rebuilding Koffan"
    cd /opt/koffan || exit
    $STD go build -o koffan main.go
    msg_ok "Rebuild Koffan"

    msg_info "Starting Service"
    systemctl start koffan
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
