#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/lgazo/drawio-mcp-server

APP="Draw.io MCP Server"
var_tags="${var_tags:-diagram;mcp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_hostname="${var_hostname:-drawio}"

function install_script() {
  msg_info "Installing Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing Draw.io MCP Server"
  $STD npm install -g drawio-mcp-server@latest
  msg_ok "Installed Draw.io MCP Server"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/drawio-mcp-server.service
[Unit]
Description=Draw.io MCP Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=drawio-mcp-server --editor --transport http --host 0.0.0.0 --http-port 80
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now drawio-mcp-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access the editor using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}The MCP endpoint is available at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}/mcp${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/drawio-mcp-server.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  msg_info "Updating Draw.io MCP Server"
  $STD npm install -g drawio-mcp-server@latest
  systemctl restart drawio-mcp-server
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
