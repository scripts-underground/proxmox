#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ntfy.sh/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ntfy"
var_tags="${var_tags:-notification}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up ntfy"
  setup_deb822_repo \
    "ntfy" \
    "https://archive.ntfy.sh/apt/keyring.gpg" \
    "https://archive.ntfy.sh/apt/" \
    "stable"
  $STD apt install -y ntfy
  systemctl enable -q --now ntfy
  msg_ok "Setup ntfy"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/ntfy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [ -f /etc/apt/keyrings/archive.heckel.io.gpg ]; then
    msg_info "Correcting old Ntfy Repository"
    rm -f /etc/apt/keyrings/archive.heckel.io.gpg
    rm -f /etc/apt/sources.list.d/archive.heckel.io.list
    rm -f /etc/apt/sources.list.d/archive.heckel.io.list.bak
    rm -f /etc/apt/sources.list.d/archive.heckel.io.sources
    setup_deb822_repo \
      "ntfy" \
      "https://archive.ntfy.sh/apt/keyring.gpg" \
      "https://archive.ntfy.sh/apt/" \
      "stable"
    msg_ok "Corrected old Ntfy Repository"
  fi
  msg_info "Updating ntfy"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated ntfy"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot see the caller
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
