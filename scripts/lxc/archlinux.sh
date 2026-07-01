#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://archlinux.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Arch Linux"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-archlinux}"
var_version="${var_version:-base}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  # This space intentionally left blank — build_container handles setup/teardown
  true
}

function post_install_script() {
  msg_ok "Completed successfully!"
  msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Arch Linux LXC"
  $STD pacman -Syu --noconfirm
  msg_ok "Updated Arch Linux LXC"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")

