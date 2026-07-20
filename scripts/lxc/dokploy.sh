#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://dokploy.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dokploy"
var_tags="${var_tags:-docker;paas}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  $STD apt install -y git openssl redis
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This script will run an external installer from https://dokploy.com/"
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_info "→  https://dokploy.com/install.sh"

  msg_info "Installing ${APP} (Patience)"
  $STD bash <(curl -fsSL https://dokploy.com/install.sh)
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /etc/dokploy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD bash <(curl -fsSL https://dokploy.com/install.sh)
  msg_ok "Updated ${APP}"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
