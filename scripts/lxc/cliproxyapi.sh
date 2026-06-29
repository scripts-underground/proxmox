#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: mathiasnagler
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/router-for-me/CLIProxyAPI

APP="CLIProxyAPI"
var_tags="${var_tags:-ai;proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "cliproxyapi" "router-for-me/CLIProxyAPI" "prebuild" "latest" "/opt/cliproxyapi" "CLIProxyAPI_*_linux_amd64.tar.gz"

  msg_info "Configuring CLIProxyAPI"
  MANAGEMENT_PASSWORD=$(openssl rand -hex 32)
  API_KEY="sk-$(openssl rand -hex 16)"

  cat << EOF > /opt/cliproxyapi/config.yaml
host: ""
port: 8317
auth-dir: "/root/.cli-proxy-api"
remote-management:
  allow-remote: true
  secret-key: "${MANAGEMENT_PASSWORD}"
api-keys:
  - "${API_KEY}"
request-retry: 3
quota-exceeded:
  switch-project: true
  switch-preview-model: true
routing:
  strategy: "round-robin"
EOF

  msg_ok "Configured CLIProxyAPI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/cliproxyapi.service
[Unit]
Description=CLIProxyAPI
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/cliproxyapi
ExecStart=/opt/cliproxyapi/cli-proxy-api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cliproxyapi
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8317${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/cliproxyapi ]]; then
    msg_error "No CLIProxyAPI Installation Found!"
    exit
  fi

  if check_for_gh_release "cliproxyapi" "router-for-me/CLIProxyAPI"; then
    msg_info "Stopping CLIProxyAPI"
    systemctl stop cliproxyapi
    msg_ok "Stopped CLIProxyAPI"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cliproxyapi" "router-for-me/CLIProxyAPI" "prebuild" "latest" "/opt/cliproxyapi" "CLIProxyAPI_*_linux_amd64.tar.gz"

    msg_info "Starting CLIProxyAPI"
    systemctl start cliproxyapi
    msg_ok "Started CLIProxyAPI"

    msg_ok "Updated Successfully"
  fi
  exit
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
