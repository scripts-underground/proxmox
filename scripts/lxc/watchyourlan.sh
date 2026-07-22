#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/aceberg/WatchYourLAN

APP="WatchYourLAN"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    arp-scan \
    ieee-data \
    libwww-perl
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "watchyourlan" "aceberg/WatchYourLAN" "binary"

  msg_info "Configuring WatchYourLAN"
  mkdir -p /data
  cat << EOF > /data/config.yaml
arp_timeout: "500"
auth: false
auth_expire: 7d
auth_password: ""
auth_user: ""
color: dark
dbpath: /data/db.sqlite
guiip: 0.0.0.0
guiport: "8840"
history_days: "30"
iface: eth0
ignoreip: "no"
loglevel: verbose
shoutrrr_url: ""
theme: solar
timeout: 60
EOF
  msg_ok "Configured WatchYourLAN"

  msg_info "Creating Service"
  sed -i 's|/etc/watchyourlan/config.yaml|/data/config.yaml|' /lib/systemd/system/watchyourlan.service
  systemctl enable -q --now watchyourlan
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8840${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /lib/systemd/system/watchyourlan.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "watchyourlan" "aceberg/WatchYourLAN"; then
    msg_info "Stopping service"
    systemctl stop watchyourlan
    msg_ok "Service stopped"

    cp -R /data/config.yaml ~/config.yaml
    fetch_and_deploy_gh_release "watchyourlan" "aceberg/WatchYourLAN" "binary"
    cp -R ~/config.yaml /data/config.yaml
    sed -i 's|/etc/watchyourlan/config.yaml|/data/config.yaml|' /lib/systemd/system/watchyourlan.service
    rm ~/config.yaml

    msg_info "Starting service"
    systemctl enable -q --now watchyourlan
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
