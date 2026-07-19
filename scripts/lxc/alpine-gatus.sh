#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/TwiN/gatus

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-gatus"
var_tags="${var_tags:-alpine;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apk add --no-cache \
    ca-certificates \
    libcap-setcap
  $STD apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community go
  msg_ok "Installed dependencies"

  RELEASE=$(curl -s https://api.github.com/repos/TwiN/gatus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  msg_info "Installing gatus v${RELEASE}"
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
  msg_ok "Installed gatus v${RELEASE}"

  msg_info "Enabling gatus Service"
  cat << EOF > /etc/init.d/gatus
#!/sbin/openrc-run
description="gatus Service"
directory="/opt/gatus"
command="/opt/gatus/gatus"
command_args=""
command_background="true"
command_user="root"
pidfile="/var/run/gatus.pid"

export GATUS_CONFIG_PATH=""
export GATUS_LOG_LEVEL="INFO"
export PORT="8080"

depend() {
    use net
}
EOF
  chmod +x /etc/init.d/gatus
  $STD rc-update add gatus default
  msg_ok "Enabled gatus Service"

  msg_info "Starting gatus"
  $STD rc-service gatus start
  msg_ok "Started gatus"

  msg_info "Cleaning up"
  rm -f "$temp_file"
  $STD apk cache clean
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
  if [[ ! -d /opt/gatus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -s https://api.github.com/repos/TwiN/gatus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [ "${RELEASE}" != "$(cat /opt/gatus_version.txt)" ] || [ ! -f /opt/gatus_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    $STD apk -U upgrade
    $STD rc-service gatus stop
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
    $STD rc-service gatus start
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
