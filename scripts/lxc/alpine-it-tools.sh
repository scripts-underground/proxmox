#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: nicedevil007 (NiceDevil)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://it-tools.tech/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-IT-Tools"
var_tags="${var_tags:-alpine;development}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache \
    nginx \
    python3
  msg_ok "Installed Dependencies"

  msg_info "Installing IT-Tools"
  RELEASE=$(curl -fsSL https://api.github.com/repos/sharevb/it-tools/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
  curl -fsSL "https://github.com/sharevb/it-tools/releases/download/${RELEASE}/it-tools-${RELEASE#v}.zip" -o it-tools.zip
  mkdir -p /usr/share/nginx/html
  $STD unzip it-tools.zip -d /tmp/
  mv /tmp/dist/* /usr/share/nginx/html
  cat << 'EOF' > /etc/nginx/http.d/default.conf
server {
  listen 80;
  server_name localhost;
  root /usr/share/nginx/html;
  index index.html;

  location / {
      try_files $uri $uri/ /index.html;
  }
}
EOF
  $STD rc-update add nginx default
  $STD rc-service nginx start
  echo "${RELEASE}" > /opt/alpine-it-tools_version.txt
  msg_ok "Installed IT-Tools"

  msg_info "Cleaning up"
  rm -rf /tmp/dist
  rm -f it-tools.zip
  $STD apk cache clean
  msg_ok "Cleaned"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info

  if [ ! -d /usr/share/nginx/html ]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/sharevb/it-tools/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
  if [ "${RELEASE}" != "$(cat /opt/alpine-it-tools_version.txt)" ] || [ ! -f /opt/alpine-it-tools_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    $STD apk -U upgrade
    curl -fsSL "https://github.com/sharevb/it-tools/releases/download/${RELEASE}/it-tools-${RELEASE#v}.zip" -o it-tools.zip
    mkdir -p /usr/share/nginx/html
    rm -rf /usr/share/nginx/html/*
    $STD unzip it-tools.zip -d /tmp
    cp -r /tmp/dist/* /usr/share/nginx/html
    rm -rf /tmp/dist
    rm -f it-tools.zip
    echo "${RELEASE}" > /opt/alpine-it-tools_version.txt
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
