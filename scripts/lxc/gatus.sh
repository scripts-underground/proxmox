#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/TwiN/gatus

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Gatus"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y golang-go ca-certificates libcap2-bin
  msg_ok "Installed Dependencies"

  RELEASE=$(curl -s https://api.github.com/repos/TwiN/gatus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  msg_info "Installing Gatus v${RELEASE}"
  temp_file=$(mktemp)
  mkdir -p /opt/gatus
  curl -fsSL "https://github.com/TwiN/gatus/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
  tar zxf "$temp_file" --strip-components=1 -C /opt/gatus
  cd /opt/gatus || exit
  $STD go mod tidy
  CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o gatus .
  setcap CAP_NET_RAW+ep gatus
  mv config.yaml config
  echo "${RELEASE}" > /opt/gatus_version.txt
  msg_ok "Installed Gatus v${RELEASE}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gatus.service
[Unit]
Description=Gatus Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gatus
ExecStart=/opt/gatus/gatus
Restart=on-failure
Environment=GATUS_CONFIG_PATH=
Environment=GATUS_LOG_LEVEL=INFO
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gatus
  msg_ok "Created Service"

  msg_info "Cleaning Up"
  rm -f "$temp_file"
  msg_ok "Cleaned"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/gatus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -s https://api.github.com/repos/TwiN/gatus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [ "${RELEASE}" != "$(cat /opt/gatus_version.txt)" ] || [ ! -f /opt/gatus_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    $STD apt update
    $STD apt upgrade -y
    systemctl stop gatus
    mv /opt/gatus/config/config.yaml /opt
    rm -rf /opt/gatus/*
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/TwiN/gatus/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
    tar zxf "$temp_file" --strip-components=1 -C /opt/gatus
    cd /opt/gatus || exit
    $STD go mod tidy
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o gatus .
    setcap CAP_NET_RAW+ep gatus
    mv /opt/config.yaml config
    rm -f "$temp_file"
    echo "${RELEASE}" > /opt/gatus_version.txt
    systemctl start gatus
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
