#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://runtipi.io/ | https://github.com/runtipi/runtipi

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Runtipi"
var_tags="${var_tags:-docker;hosting}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  msg_warn "WARNING: This script will run an external installer from https://runtipi.io/"
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_info "→  https://raw.githubusercontent.com/runtipi/runtipi/master/scripts/install.sh"

  msg_info "Installing ${APP} (Patience)"
  DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
  mkdir -p "$(dirname "$DOCKER_CONFIG_PATH")"
  [[ ! -f "$DOCKER_CONFIG_PATH" ]] && echo -e '{\n  "log-driver": "journald"\n}' > "$DOCKER_CONFIG_PATH"
  cd /opt || exit
  $STD bash <(curl -fsSL https://raw.githubusercontent.com/runtipi/runtipi/master/scripts/install.sh)
  chmod 660 /opt/runtipi/state/settings.json 2> /dev/null || true
  rm -f /opt/install.sh
  msg_ok "Installed ${APP}"
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

  if [[ ! -d /opt/runtipi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  cd /opt/runtipi || exit
  $STD ./runtipi-cli update latest
  msg_ok "Updated ${APP}"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
