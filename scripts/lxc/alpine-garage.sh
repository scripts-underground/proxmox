#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://garagehq.deuxfleurs.fr/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Garage"
var_tags="${var_tags:-alpine;object-storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)

  msg_info "Installing Dependencies"
  $STD apk add --no-cache openssl
  msg_ok "Installed Dependencies"

  msg_info "Installing Garage"
  GARAGE_RELEASE=$(curl -s https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
  curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_RELEASE}/${ARCH}-unknown-linux-musl/garage" -o /usr/local/bin/garage
  chmod +x /usr/local/bin/garage
  msg_ok "Installed Garage"

  msg_info "Enabling Garage Service"
  cat << EOF > /etc/init.d/garage
#!/sbin/openrc-run
description="Garage Object Storage"
command="/usr/local/bin/garage"
command_args="server /etc/garage/garage.toml"
command_background="true"
pidfile="/var/run/garage.pid"
EOF
  chmod +x /etc/init.d/garage
  $STD rc-update add garage default
  msg_ok "Enabled Garage Service"

  msg_info "Starting Garage"
  $STD rc-service garage start
  msg_ok "Started Garage"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3903${CL}"
}

function update_script() {
  header_info
  if [[ ! -f /usr/local/bin/garage ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"

  ARCH=$(uname -m)
  GARAGE_RELEASE=$(curl -s https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
  msg_info "Updating Garage to ${GARAGE_RELEASE}"
  curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_RELEASE}/${ARCH}-unknown-linux-musl/garage" -o /usr/local/bin/garage
  chmod +x /usr/local/bin/garage
  msg_ok "Updated Garage to ${GARAGE_RELEASE}"

  $STD rc-service garage restart
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
