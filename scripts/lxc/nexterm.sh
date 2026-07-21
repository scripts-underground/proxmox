#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Mathias Wagner (gnmyt)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nexterm.dev/

# shellcheck disable=SC2034
APP="Nexterm"
var_tags="${var_tags:-server-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NEXTERM_ARCH=$(uname -m)
  [[ "$NEXTERM_ARCH" == "x86_64" ]] && NEXTERM_ARCH="x64"
  [[ "$NEXTERM_ARCH" == "aarch64" ]] && NEXTERM_ARCH="arm64"

  fetch_and_deploy_gh_release "nexterm-engine" "gnmyt/Nexterm" "prebuild" "latest" "/opt/nexterm/engine" "nexterm-engine-linux-${NEXTERM_ARCH}.tar.gz"
  fetch_and_deploy_gh_release "nexterm-server" "gnmyt/Nexterm" "singlefile" "latest" "/opt/nexterm/server" "nexterm-server-linux-${NEXTERM_ARCH}"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/nexterm-engine.service
[Unit]
Description=Nexterm Engine
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/nexterm/engine/nexterm-engine
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/nexterm-server.service
[Unit]
Description=Nexterm Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/nexterm/server/nexterm-server
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now nexterm-engine
  systemctl enable -q --now nexterm-server
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6989${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/nexterm/server/nexterm-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NEXTERM_ARCH=$(uname -m)
  [[ "$NEXTERM_ARCH" == "x86_64" ]] && NEXTERM_ARCH="x64"
  [[ "$NEXTERM_ARCH" == "aarch64" ]] && NEXTERM_ARCH="arm64"

  if check_for_gh_release "nexterm-engine" "gnmyt/Nexterm"; then
    msg_info "Stopping nexterm-engine"
    systemctl stop nexterm-engine
    msg_ok "Stopped nexterm-engine"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nexterm-engine" "gnmyt/Nexterm" "prebuild" "latest" "/opt/nexterm/engine" "nexterm-engine-linux-${NEXTERM_ARCH}.tar.gz"

    msg_info "Starting nexterm-engine"
    systemctl start nexterm-engine
    msg_ok "Started nexterm-engine"
  fi

  if check_for_gh_release "nexterm-server" "gnmyt/Nexterm"; then
    msg_info "Stopping nexterm-server"
    systemctl stop nexterm-server
    msg_ok "Stopped nexterm-server"

    fetch_and_deploy_gh_release "nexterm-server" "gnmyt/Nexterm" "singlefile" "latest" "/opt/nexterm/server" "nexterm-server-linux-${NEXTERM_ARCH}"

    msg_info "Starting nexterm-server"
    systemctl start nexterm-server
    msg_ok "Started nexterm-server"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
