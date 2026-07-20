#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/matter-js/python-matter-server

APP="Matter-Server"
var_tags="${var_tags:-matter;iot;smart-home}"
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
    libuv1 \
    libjson-c5 \
    libnl-3-200 \
    libnl-route-3-200 \
    iputils-ping \
    iproute2
  msg_ok "Installed Dependencies"

  UV_PYTHON="3.12" setup_uv

  msg_info "Setting up Matter Server"
  mkdir -p /opt/matter-server/data/credentials
  if [ -L /data ]; then
    rm -f /data
  fi
  if [ ! -e /data ]; then
    ln -s /opt/matter-server/data /data
  fi
  $STD uv venv /opt/matter-server/.venv
  MATTER_VERSION=$(get_latest_github_release "matter-js/python-matter-server")
  $STD uv pip install --python /opt/matter-server/.venv/bin/python "python-matter-server[server]==${MATTER_VERSION}"
  echo "${MATTER_VERSION}" > ~/.matter-server
  msg_ok "Set up Matter Server"

  msg_info "Configuring Network"
  cat << EOF > /etc/sysctl.d/99-matter.conf
net.ipv4.igmp_max_memberships=1024
EOF
  $STD sysctl -p /etc/sysctl.d/99-matter.conf
  msg_ok "Configured Network"

  if [[ "$(get_system_arch)" == "arm64" ]]; then
    CHIP_ARCH="aarch64"
  else
    CHIP_ARCH="x86-64"
  fi
  fetch_and_deploy_gh_release "chip-ota-provider-app" "home-assistant-libs/matter-linux-ota-provider" "singlefile" "latest" "/usr/local/bin" "chip-ota-provider-app-${CHIP_ARCH}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/matter-server.service
[Unit]
Description=Matter Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/matter-server/.venv/bin/matter-server --storage-path /data --paa-root-cert-dir /data/credentials
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now matter-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Matter Server WebSocket API is running on port 5580.${CL}"
  echo -e "${GATEWAY}${BGN}ws://${IP}:5580/ws${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/matter-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "matter-server" "matter-js/python-matter-server"; then
    msg_info "Stopping Service"
    systemctl stop matter-server
    msg_ok "Stopped Service"

    msg_info "Updating Matter Server"
    MATTER_VERSION=$(get_latest_github_release "matter-js/python-matter-server")
    $STD uv pip install --python /opt/matter-server/.venv/bin/python --upgrade "python-matter-server[server]==${MATTER_VERSION}"
    echo "${MATTER_VERSION}" > ~/.matter-server
    msg_ok "Updated Matter Server"

    if [[ "$(get_system_arch)" == "arm64" ]]; then
      CHIP_ARCH="aarch64"
    else
      CHIP_ARCH="x86-64"
    fi
    fetch_and_deploy_gh_release "chip-ota-provider-app" "home-assistant-libs/matter-linux-ota-provider" "singlefile" "latest" "/usr/local/bin" "chip-ota-provider-app-${CHIP_ARCH}"

    msg_info "Starting Service"
    systemctl start matter-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
