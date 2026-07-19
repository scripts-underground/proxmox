#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://actualbudget.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Actual Budget"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    make \
    g++
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  create_self_signed_cert

  msg_info "Installing Actual Budget"
  cd /opt || exit
  RELEASE=$(get_latest_github_release "actualbudget/actual")
  mkdir -p /opt/actualbudget-data/{server-files,upload,migrate,user-files,migrations,config}
  chown -R root:root /opt/actualbudget-data
  chmod -R 755 /opt/actualbudget-data

  cat << EOF > /opt/actualbudget-data/config.json
{
  "port": 5006,
  "hostname": "::",
  "serverFiles": "/opt/actualbudget-data/server-files",
  "userFiles": "/opt/actualbudget-data/user-files",
  "trustedProxies": [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "127.0.0.0/8",
    "::1/128",
    "fc00::/7"
  ],
  "https": {
    "key": "/etc/ssl/actualbudget/actualbudget.key",
    "cert": "/etc/ssl/actualbudget/actualbudget.crt"
  }
}
EOF
  mkdir -p /opt/actualbudget
  cd /opt/actualbudget || exit
  $STD npm install --location=global @actual-app/sync-server
  echo "${RELEASE}" > ~/.actualbudget
  msg_ok "Installed Actual Budget"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/actualbudget.service
[Unit]
Description=Actual Budget Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/actualbudget
Environment=ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB=20
Environment=ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB=50
Environment=ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB=20
ExecStart=/usr/bin/actual-server --config /opt/actualbudget-data/config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now actualbudget
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:5006${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f ~/.actualbudget && ! -f /opt/actualbudget_version.txt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs
  RELEASE=$(get_latest_github_release "actualbudget/actual")
  if [[ -f /opt/actualbudget-data/config.json ]]; then
    if check_for_gh_release "actualbudget" "actualbudget/actual"; then
      msg_info "Stopping Service"
      systemctl stop actualbudget
      msg_ok "Stopped Service"

      msg_info "Updating Actual Budget to ${RELEASE}"
      $STD npm update -g @actual-app/sync-server
      echo "${RELEASE}" > ~/.actualbudget
      msg_ok "Updated Actual Budget to ${RELEASE}"

      msg_info "Starting Service"
      systemctl start actualbudget
      msg_ok "Started Service"
      msg_ok "Updated successfully!"
    fi
  else
    msg_warn "Old Installation Found, you need to migrate your data and recreate to a new container"
    msg_warn "Please follow the instructions on the Actual Budget website to migrate your data"
    msg_warn "https://actualbudget.org/docs/backup-restore/backup"
    exit
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
