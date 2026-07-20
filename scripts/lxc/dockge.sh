#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://dockge.kuma.pet/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dockge"
var_tags="${var_tags:-docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-18}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  msg_ok "Installed Dependencies"

  msg_info "Creating Directories"
  mkdir -p /opt/dockge /opt/stacks
  msg_ok "Created Directories"

  msg_info "Downloading Compose File"
  curl -fsSL "https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml" -o /opt/dockge/compose.yaml
  msg_ok "Downloaded Compose File"

  msg_info "Starting ${APP}"
  cd /opt/dockge || exit
  $STD docker compose up -d
  msg_ok "Started ${APP}"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5001${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/dockge ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  cd /opt/dockge || exit
  $STD docker compose pull
  $STD docker compose up -d
  msg_ok "Updated ${APP}"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
