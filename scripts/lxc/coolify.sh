#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://coolify.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Coolify"
var_tags="${var_tags:-docker;paas}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  $STD apt install -y git openssl
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This script will run an external installer from https://coolify.io/"
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_info "→  https://cdn.coollabs.io/coolify/install.sh"

  msg_info "Installing ${APP} (Patience)"
  $STD bash <(curl -fsSL https://cdn.coollabs.io/coolify/install.sh)
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /data/coolify ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD bash <(curl -fsSL https://cdn.coollabs.io/coolify/install.sh)
  msg_ok "Updated ${APP}"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
