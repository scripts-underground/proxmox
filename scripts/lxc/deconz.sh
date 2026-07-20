#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.phoscon.de/en/conbee2/software#deconz

# shellcheck disable=SC2034
APP="deCONZ"
var_tags="${var_tags:-zigbee}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Setting Phoscon Repository"
  setup_deb822_repo \
    "deconz" \
    "https://phoscon.de/apt/deconz.pub.key" \
    "https://phoscon.de/apt/deconz" \
    "generic"
  msg_ok "Setup Phoscon Repository"

  msg_info "Installing deConz"
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    pool="https://security.ubuntu.com/ubuntu/pool/main/o/openssl/"
  else
    pool="http://ports.ubuntu.com/ubuntu-ports/pool/main/o/openssl/"
  fi
  arch_suffix="$([ "$ARCH" = "x86_64" ] && echo "amd64" || echo "arm64")"
  libssl=$(curl -fsSL --proto '=http,https' "$pool" | grep -o "libssl1\.1_1\.1\.1f-1ubuntu2\.2[^\"]*${arch_suffix}\.deb" | head -n1)
  curl -fsSL --proto '=http,https' "$pool$libssl" -o "$libssl"
  $STD dpkg -i "$libssl"
  $STD apt install -y deconz
  rm -rf "$libssl"
  msg_ok "Installed deConz"

  msg_info "Creating Service"
  cat << 'EOF' > /lib/systemd/system/deconz.service
[Unit]
Description=deCONZ: ZigBee gateway -- REST API
Wants=deconz-init.service deconz-update.service
StartLimitIntervalSec=0

[Service]
User=root
ExecStart=/usr/bin/deCONZ -platform minimal --http-port=80
Restart=on-failure
RestartSec=30
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_KILL CAP_SYS_BOOT CAP_SYS_TIME

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now deconz
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/sources.list.d/deconz.list && ! -f /etc/apt/sources.list.d/deconz.sources ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating deCONZ"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated deCONZ"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
