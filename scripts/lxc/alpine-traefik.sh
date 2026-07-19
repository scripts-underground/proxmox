#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://alpinelinux.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Traefik"
var_tags="${var_tags:-os;alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Traefik"
  $STD apk add ca-certificates
  $STD apk add traefik --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community
  msg_ok "Installed Traefik"

  read -p "${TAB3}Enable Traefik WebUI (Port 8080)? [y/N]: " enable_webui
  if [[ "$enable_webui" =~ ^[Yy]$ ]]; then
    msg_info "Configuring Traefik WebUI"
    sed -i 's/localhost//g' /etc/traefik/traefik.yaml
    msg_ok "Configured Traefik WebUI"
  fi

  msg_info "Enabling and starting Traefik service"
  $STD rc-update add traefik default
  sed -i '/^command=.*/i directory="/etc/traefik"' /etc/init.d/traefik
  $STD rc-service traefik start
  msg_ok "Traefik service started"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Traefik"
  rc-service traefik restart
  msg_ok "Restarted Traefik"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
