#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# Co-Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://n8n.io/

APP="n8n"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3-setuptools \
    graphicsmagick
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing n8n (Patience)"
  $STD npm install -g n8n@latest
  msg_ok "Installed n8n"

  msg_info "Creating Service"
  cat << EOF > /opt/n8n.env
N8N_SECURE_COOKIE=false
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=$(hostname -I | awk '{print $1}')
EOF

  cat << EOF > /etc/systemd/system/n8n.service
[Unit]
Description=n8n

[Service]
Type=simple
EnvironmentFile=/opt/n8n.env
ExecStart=n8n start

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now n8n
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5678${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/n8n.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies build-essential python3-setuptools graphicsmagick
  NODE_VERSION="24" setup_nodejs

  msg_info "Updating n8n"
  if [ ! -f /opt/n8n.env ]; then
    sed -i 's|^Environment="N8N_SECURE_COOKIE=false"$|EnvironmentFile=/opt/n8n.env|' /etc/systemd/system/n8n.service
    mkdir -p /opt
    cat << EOF > /opt/n8n.env
N8N_SECURE_COOKIE=false
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=$(hostname -I | awk '{print $1}')
EOF
    systemctl daemon-reload
  fi

  $STD npm install -g n8n@latest
  systemctl restart n8n
  msg_ok "Updated n8n"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
