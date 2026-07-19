#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://casaos.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CasaOS"
var_tags="${var_tags:-cloud}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_warn "WARNING: This script will run an external installer from a third-party source (https://casaos.zimaspace.com/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_info "→  https://get.casaos.io/"

  setup_docker

  msg_info "Installing CasaOS (Patience)"
  $STD bash <(curl -fsSL https://get.casaos.io/)
  msg_ok "Installed CasaOS"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/casaos ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
