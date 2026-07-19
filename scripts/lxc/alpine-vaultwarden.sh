#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://vaultwarden.ekdevops.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Vaultwarden"
var_tags="${var_tags:-alpine;password}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Vaultwarden"
  $STD apk add vaultwarden
  echo -e "export ADMIN_TOKEN=''" >> /etc/conf.d/vaultwarden
  echo -e "export ROCKET_ADDRESS=0.0.0.0" >> /etc/conf.d/vaultwarden
  echo -e "export ROCKET_TLS='{certs=\"/etc/ssl/certs/vaultwarden-selfsigned.crt\",key=\"/etc/ssl/private/vaultwarden-selfsigned.key\"}'" >> /etc/conf.d/vaultwarden
  $STD openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /etc/ssl/private/vaultwarden-selfsigned.key -out /etc/ssl/certs/vaultwarden-selfsigned.crt -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
  chown vaultwarden:vaultwarden /etc/ssl/certs/vaultwarden-selfsigned.crt
  chown vaultwarden:vaultwarden /etc/ssl/private/vaultwarden-selfsigned.key
  msg_ok "Installed Alpine-Vaultwarden"

  msg_info "Installing Web-Vault"
  $STD apk add --no-cache vaultwarden-web-vault
  msg_ok "Installed Web-Vault"

  msg_info "Starting Alpine-Vaultwarden"
  $STD rc-service vaultwarden start
  $STD rc-update add vaultwarden default
  msg_ok "Started Alpine-Vaultwarden"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8443${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Vaultwarden"
  rc-service vaultwarden restart
  msg_ok "Restarted Vaultwarden"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
